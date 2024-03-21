#########################################################################
#  OpenKore - Miscellaneous functions
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 6792 $
#  $Id: Misc.pm 6792 2009-07-28 08:38:34Z klabmouse $
#
#########################################################################
##
# MODULE DESCRIPTION: Miscellaneous functions
#
# This module contains functions that do not belong in any other modules.
# The difference between Misc.pm and Utils.pm is that Misc.pm can have
# dependencies on other Kore modules.

package Misc;

use strict;
use Exporter;
use Carp::Assert;
use Data::Dumper;
use Compress::Zlib;
use base qw(Exporter);
use encoding 'utf8';

use Globals;
use Log qw(message warning error debug);
use Plugins;
use FileParsers;
use Settings;
use Utils;
use Utils::Assert;
use Skill;
use Field;
use Network;
use Network::Send ();
use AI;
use Actor;
use Actor::You;
use Actor::Player;
use Actor::Monster;
use Actor::Party;
use Actor::NPC;
use Actor::Portal;
use Actor::Pet;
use Actor::Slave;
use Actor::Unknown;
use Time::HiRes qw(time usleep);
use Translation;
use Utils::Exceptions;

our @EXPORT = (
	# Config modifiers
	qw/auth
	configModify
	bulkConfigModify
	setTimeout
	saveConfigFile/,

	# Debugging
	qw/debug_showSpots
	visualDump/,

	# Field math
	qw/calcRectArea
	calcRectArea2
	checkLineSnipable
	checkLineWalkable
	checkWallLength
	closestWalkableSpot
	objectInsideSpell
	objectIsMovingTowards
	objectIsMovingTowardsPlayer/,

	# Inventory management
	qw/inInventory
	inventoryItemRemoved
	storageGet
	cardName
	itemName
	itemNameSimple/,

	# File Parsing and Writing
	qw/chatLog
	shopLog
	monsterLog/,

	# Logging
	qw/itemLog/,

	# OS specific
	qw/launchURL/,

	# Misc
	qw/
	actorAdded
	actorRemoved
	actorListClearing
	avoidGM_talk
	avoidList_talk
	avoidList_ID
	calcStat
	center
	charSelectScreen
	chatLog_clear
	checkAllowedMap
	checkFollowMode
	checkMonsterCleanness
	createCharacter
	deal
	dealAddItem
	drop
	dumpData
	getEmotionByCommand
	getIDFromChat
	getNPCName
	getPlayerNameFromCache
	getPortalDestName
	getResponse
	getSpellName
	headgearName
	initUserSeed
	itemLog_clear
	look
	lookAtPosition
	manualMove
	meetingPosition
	objectAdded
	objectRemoved
	items_control
	pickupitems
	mon_control
	positionNearPlayer
	positionNearPortal
	printItemDesc
	processNameRequestQueue
	quit
	relog
	sendMessage
	setSkillUseTimer
	setPartySkillTimer
	setStatus
	countCastOn
	stopAttack
	stripLanguageCode
	switchConfigFile
	updateDamageTables
	updatePlayerNameCache
	useTeleport
	top10Listing
	whenGroundStatus
	whenStatusActive
	whenStatusActiveMon
	whenStatusActivePL
	writeStorageLog
	getBestTarget
	isSafe/,

	# Actor's Actions Text
	qw/attack_string
	skillCast_string
	skillUse_string
	skillUseLocation_string
	skillUseNoDamage_string
	status_string/,

	# AI Math
	qw/lineIntersection
	percent_hp
	percent_sp
	percent_weight/,

	# Misc Functions
	qw/avoidGM_near
	avoidList_near
	compilePortals
	compilePortals_check
	portalExists
	portalExists2
	redirectXKoreMessages
	monKilled
	getActorName
	getActorNames
	findPartyUserID
	getNPCInfo
	skillName
	checkSelfCondition
	checkPlayerCondition
	checkMonsterCondition
	findCartItemInit
	findCartItem
	makeShop
	openShop
	closeShop
	inLockMap
	parseReload/
	);


# use SelfLoader; 1;
# __DATA__



sub _checkActorHash($$$$) {
	my ($name, $hash, $type, $hashName) = @_;
	foreach my $actor (values %{$hash}) {
		if (!UNIVERSAL::isa($actor, $type)) {
			die "$name\nUnblessed item in $hashName list:\n" .
				Dumper($hash);
		}
	}
}

# Checks whether the internal state of some variables are correct.
sub checkValidity {
	return if (!DEBUG || $ENV{OPENKORE_NO_CHECKVALIDITY});
	my ($name) = @_;
	$name = "Validity check:" if (!defined $name);

	assertClass($char, 'Actor::You') if ($net && $net->getState() == Network::IN_GAME
						&& $net->isa('Network::XKore'));
	assertClass($char, 'Actor::You') if ($char);
	return;

	_checkActorHash($name, \%items, 'Actor::Item', 'item');
	_checkActorHash($name, \%monsters, 'Actor::Monster', 'monster');
	_checkActorHash($name, \%players, 'Actor::Player', 'player');
	_checkActorHash($name, \%pets, 'Actor::Pet', 'pet');
	_checkActorHash($name, \%npcs, 'Actor::NPC', 'NPC');
	_checkActorHash($name, \%portals, 'Actor::Portal', 'portals');
}


#######################################
#######################################
### CATEGORY: Configuration modifiers
#######################################
#######################################

sub auth {
	my $user = shift;
	my $flag = shift;
	if ($flag) {
		message TF("Authorized user '%s' for admin\n", $user), "success";
	} else {
		message TF("Revoked admin privilages for user '%s'\n", $user), "success";
	}
	$overallAuth{$user} = $flag;
	writeDataFile(Settings::getControlFilename("overallAuth.txt"), \%overallAuth);
}

##
# void configModify(String key, String value, ...)
# key: a key name.
# value: the new value.
#
# Changes the value of the configuration option $key to $value.
# Both %config and config.txt will be updated.
#
# You may also call configModify() with additional optional options:
# `l
# - autoCreate (boolean): Whether the configuration option $key
#                         should be created if it doesn't already exist.
#                         The default is true.
# - silent (boolean): By default, output will be printed, notifying the user
#                     that a config option has been changed. Setting this to
#                     true will surpress that output.
# `l`
sub configModify {
	my $key = shift;
	my $val = shift;
	my %args;

	if (@_ == 1) {
		$args{silent} = $_[0];
	} else {
		%args = @_;
	}
	$args{autoCreate} = 1 if (!exists $args{autoCreate});

	Plugins::callHook('configModify', {
		key => $key,
		val => $val,
		additionalOptions => \%args
	});

	if (!$args{silent} && $key !~ /password/i) {
		my $oldval = $config{$key};
		if (!defined $oldval) {
			$oldval = "not set";
		}

		if (!defined $val) {
			message TF("Config '%s' unset (was %s)\n", $key, $oldval), "info";
		} else {
			message TF("Config '%s' set to %s (was %s)\n", $key, $val, $oldval), "info";
		}
	}
	if ($args{autoCreate} && !exists $config{$key}) {
		my $f;
		if (open($f, ">>", Settings::getConfigFilename())) {
			print $f "$key\n";
			close($f);
		}
	}
	$config{$key} = $val;
	saveConfigFile();
}

##
# bulkConfigModify (r_hash, [silent])
# r_hash: key => value to change
# silent: if set to 1, do not print a message to the console.
#
# like configModify but for more than one value at the same time.
sub bulkConfigModify {
	my $r_hash = shift;
	my $silent = shift;
	my $oldval;

	foreach my $key (keys %{$r_hash}) {
		Plugins::callHook('configModify', {
			key => $key,
			val => $r_hash->{$key},
			silent => $silent
		});

		$oldval = $config{$key};

		$config{$key} = $r_hash->{$key};

		if ($key =~ /password/i) {
			message TF("Config '%s' set to %s (was *not-displayed*)\n", $key, $r_hash->{$key}), "info" unless ($silent);
		} else {
			message TF("Config '%s' set to %s (was %s)\n", $key, $r_hash->{$key}, $oldval), "info" unless ($silent);
		}
	}
	saveConfigFile();
}

##
# saveConfigFile()
#
# Writes %config to config.txt.
sub saveConfigFile {
	writeDataFileIntact(Settings::getConfigFilename(), \%config);
}

sub setTimeout {
	my $timeout = shift;
	my $time = shift;
	message TF("Timeout '%s' set to %s (was %s)\n", $timeout, $time, $timeout{$timeout}{timeout}), "info";
	$timeout{$timeout}{'timeout'} = $time;
	writeDataFileIntact2(Settings::getControlFilename("timeouts.txt"), \%timeout);
}


#######################################
#######################################
### Category: Debugging
#######################################
#######################################

our %debug_showSpots_list;

sub debug_showSpots {
	return unless $net->clientAlive();
	my $ID = shift;
	my $spots = shift;
	my $special = shift;

	if ($debug_showSpots_list{$ID}) {
		foreach (@{$debug_showSpots_list{$ID}}) {
			my $msg = pack("C*", 0x20, 0x01) . pack("V", $_);
			$net->clientSend($msg);
		}
	}

	my $i = 1554;
	$debug_showSpots_list{$ID} = [];
	foreach (@{$spots}) {
		next if !defined $_;
		my $msg = pack("C*", 0x1F, 0x01)
			. pack("V*", $i, 1550)
			. pack("v*", $_->{x}, $_->{y})
			. pack("C*", 0x93, 0);
		$net->clientSend($msg);
		$net->clientSend($msg);
		push @{$debug_showSpots_list{$ID}}, $i;
		$i++;
	}

	if ($special) {
		my $msg = pack("C*", 0x1F, 0x01)
			. pack("V*", 1553, 1550)
			. pack("v*", $special->{x}, $special->{y})
			. pack("C*", 0x83, 0);
		$net->clientSend($msg);
		$net->clientSend($msg);
		push @{$debug_showSpots_list{$ID}}, 1553;
	}
}

##
# visualDump(data [, label])
#
# Show the bytes in $data on screen as hexadecimal.
# Displays the label if provided.
sub visualDump {
	my ($msg, $label) = @_;
	my $dump;
	my $puncations = quotemeta '~!@#$%^&*()_-+=|\"\'';
	no encoding 'utf8';
	use bytes;

	$dump = "================================================\n";
	if (defined $label) {
		$dump .= sprintf("%-15s [%d bytes]   %s\n", $label, length($msg), getFormattedDate(int(time)));
	} else {
		$dump .= sprintf("%d bytes   %s\n", length($msg), getFormattedDate(int(time)));
	}

	for (my $i = 0; $i < length($msg); $i += 16) {
		my $line;
		my $data = substr($msg, $i, 16);
		my $rawData = '';

		for (my $j = 0; $j < length($data); $j++) {
			my $char = substr($data, $j, 1);
			if (ord($char) < 32 || ord($char) > 126) {
				$rawData .= '.';
			} else {
				$rawData .= substr($data, $j, 1);
			}
		}

		$line = getHex(substr($data, 0, 8));
		$line .= '    ' . getHex(substr($data, 8)) if (length($data) > 8);

		$line .= ' ' x (50 - length($line)) if (length($line) < 54);
		$line .= "    $rawData\n";
		$line = sprintf("%3d>  ", $i) . $line;
		$dump .= $line;
	}
	message $dump;
}


#######################################
#######################################
### CATEGORY: Field math
#######################################
#######################################

##
# calcRectArea($x, $y, $radius)
# Returns: an array with position hashes. Each has contains an x and a y key.
#
# Creates a rectangle with center ($x,$y) and radius $radius,
# and returns a list of positions of the border of the rectangle.
sub calcRectArea {
	my ($x, $y, $radius) = @_;
	my (%topLeft, %topRight, %bottomLeft, %bottomRight);

	sub capX {
		return 0 if ($_[0] < 0);
		return $field{width} - 1 if ($_[0] >= $field{width});
		return int $_[0];
	}
	sub capY {
		return 0 if ($_[0] < 0);
		return $field{height} - 1 if ($_[0] >= $field{height});
		return int $_[0];
	}

	# Get the avoid area as a rectangle
	$topLeft{x} = capX($x - $radius);
	$topLeft{y} = capY($y + $radius);
	$topRight{x} = capX($x + $radius);
	$topRight{y} = capY($y + $radius);
	$bottomLeft{x} = capX($x - $radius);
	$bottomLeft{y} = capY($y - $radius);
	$bottomRight{x} = capX($x + $radius);
	$bottomRight{y} = capY($y - $radius);

	# Walk through the border of the rectangle
	# Record the blocks that are walkable
	my @walkableBlocks;
	for (my $x = $topLeft{x}; $x <= $topRight{x}; $x++) {
		if ($field->isWalkable($x, $topLeft{y})) {
			push @walkableBlocks, {x => $x, y => $topLeft{y}};
		}
	}
	for (my $x = $bottomLeft{x}; $x <= $bottomRight{x}; $x++) {
		if ($field->isWalkable($x, $bottomLeft{y})) {
			push @walkableBlocks, {x => $x, y => $bottomLeft{y}};
		}
	}
	for (my $y = $bottomLeft{y} + 1; $y < $topLeft{y}; $y++) {
		if ($field->isWalkable($topLeft{x}, $y)) {
			push @walkableBlocks, {x => $topLeft{x}, y => $y};
		}
	}
	for (my $y = $bottomRight{y} + 1; $y < $topRight{y}; $y++) {
		if ($field->isWalkable($topLeft{x}, $y)) {
			push @walkableBlocks, {x => $topRight{x}, y => $y};
		}
	}

	return @walkableBlocks;
}

##
# calcRectArea2($x, $y, $radius, $minRange)
# Returns: an array with position hashes. Each has contains an x and a y key.
#
# Creates a rectangle with center ($x,$y) and radius $radius,
# and returns a list of positions inside the rectangle that are
# not closer than $minRange to the center.
sub calcRectArea2 {
	my ($cx, $cy, $r, $min) = @_;

	my @rectangle;
	for (my $x = $cx - $r; $x <= $cx + $r; $x++) {
		for (my $y = $cy - $r; $y <= $cy + $r; $y++) {
			next if distance({x => $cx, y => $cy}, {x => $x, y => $y}) < $min;
			push(@rectangle, {x => $x, y => $y});
		}
	}
	return @rectangle;
}

##
# checkLineSnipable(from, to)
# from, to: references to position hashes.
#
# Check whether you can snipe a target standing at $to,
# from the position $from, without being blocked by any
# obstacles.
sub checkLineSnipable {
	return 0 if (!$field);
	my $from = shift;
	my $to = shift;

	# Simulate tracing a line to the location (modified Bresenham's algorithm)
	my ($X0, $Y0, $X1, $Y1) = ($from->{x}, $from->{y}, $to->{x}, $to->{y});

	my $steep;
	my $posX = 1;
	my $posY = 1;
	if ($X1 - $X0 < 0) {
		$posX = -1;
	}
	if ($Y1 - $Y0 < 0) {
		$posY = -1;
	}
	if (abs($Y0 - $Y1) < abs($X0 - $X1)) {
		$steep = 0;
	} else {
		$steep = 1;
	}
	if ($steep == 1) {
		my $Yt = $Y0;
		$Y0 = $X0;
		$X0 = $Yt;

		$Yt = $Y1;
		$Y1 = $X1;
		$X1 = $Yt;
	}
	if ($X0 > $X1) {
		my $Xt = $X0;
		$X0 = $X1;
		$X1 = $Xt;

		my $Yt = $Y0;
		$Y0 = $Y1;
		$Y1 = $Yt;
	}
	my $dX = $X1 - $X0;
	my $dY = abs($Y1 - $Y0);
	my $E = 0;
	my $dE;
	if ($dX) {
		$dE = $dY / $dX;
	} else {
		# Delta X is 0, it only occures when $from is equal to $to
		return 1;
	}
	my $stepY;
	if ($Y0 < $Y1) {
		$stepY = 1;
	} else {
		$stepY = -1;
	}
	my $Y = $Y0;
	my $Erate = 0.99;
	if (($posY == -1 && $posX == 1) || ($posY == 1 && $posX == -1)) {
		$Erate = 0.01;
	}
	for (my $X=$X0;$X<=$X1;$X++) {
		$E += $dE;
		if ($steep == 1) {
			return 0 if (!$field->isSnipable($Y, $X));
		} else {
			return 0 if (!$field->isSnipable($X, $Y));
		}
		if ($E >= $Erate) {
			$Y += $stepY;
			$E -= 1;
		}
	}
	return 1;
}

##
# checkLineWalkable(from, to, [min_obstacle_size = 5])
# from, to: references to position hashes.
#
# Check whether you can walk from $from to $to in an (almost)
# straight line, without obstacles that are too large.
# Obstacles are considered too large, if they are at least
# the size of a rectangle with "radius" $min_obstacle_size.
sub checkLineWalkable {
	return 0 if (!$field);
	my $from = shift;
	my $to = shift;
	my $min_obstacle_size = shift;
	$min_obstacle_size = 5 if (!defined $min_obstacle_size);

	my $dist = round(distance($from, $to));
	my %vec;

	getVector(\%vec, $to, $from);
	# Simulate walking from $from to $to
	for (my $i = 1; $i < $dist; $i++) {
		my %p;
		moveAlongVector(\%p, $from, \%vec, $i);
		$p{x} = int $p{x};
		$p{y} = int $p{y};

		if ( !$field->isWalkable($p{x}, $p{y}) ) {
			# The current spot is not walkable. Check whether
			# this the obstacle is small enough.
			if (checkWallLength(\%p, -1,  0, $min_obstacle_size) || checkWallLength(\%p,  1, 0, $min_obstacle_size)
			 || checkWallLength(\%p,  0, -1, $min_obstacle_size) || checkWallLength(\%p,  0, 1, $min_obstacle_size)
			 || checkWallLength(\%p, -1, -1, $min_obstacle_size) || checkWallLength(\%p,  1, 1, $min_obstacle_size)
			 || checkWallLength(\%p,  1, -1, $min_obstacle_size) || checkWallLength(\%p, -1, 1, $min_obstacle_size)) {
				return 0;
			}
		}
	}
	return 1;
}

sub checkWallLength {
	my $pos = shift;
	my $dx = shift;
	my $dy = shift;
	my $length = shift;

	my $x = $pos->{x};
	my $y = $pos->{y};
	my $len = 0;
	do {
		last if ($x < 0 || $x >= $field{width} || $y < 0 || $y >= $field{height});
		$x += $dx;
		$y += $dy;
		$len++;
	} while (!$field->isWalkable($x, $y) && $len < $length);
	return $len >= $length;
}

##
# closestWalkableSpot(r_field, pos)
# r_field: a reference to a field hash.
# pos: reference to a position hash (which contains 'x' and 'y' keys).
# Returns: 1 if %pos has been modified, 0 of not.
#
# If the position specified in $pos is walkable, this function will do nothing.
# If it's not walkable, this function will find the closest position that is walkable (up to 2 blocks away),
# and modify the x and y values in $pos.
sub closestWalkableSpot {
	my $field = shift;
	my $pos = shift;

	foreach my $z ( [0,0], [0,1],[1,0],[0,-1],[-1,0], [-1,1],[1,1],[1,-1],[-1,-1],[0,2],[2,0],[0,-2],[-2,0] ) {
		next if !$field->isWalkable($pos->{x} + $z->[0], $pos->{y} + $z->[1]);
		$pos->{x} += $z->[0];
		$pos->{y} += $z->[1];
		return 1;
	}
	return 0;
}

##
# objectInsideSpell(object, [ignore_party_members = 1])
# object: reference to a player or monster hash.
#
# Checks whether an object is inside someone else's spell area.
# (Traps are also "area spells").
sub objectInsideSpell {
	my $object = shift;
	my $ignore_party_members = shift;
	$ignore_party_members = 1 if (!defined $ignore_party_members);

	my ($x, $y) = ($object->{pos_to}{x}, $object->{pos_to}{y});
	foreach (@spellsID) {
		my $spell = $spells{$_};
		if ((!$ignore_party_members || !$char->{party} || !$char->{party}{users}{$spell->{sourceID}})
		  && $spell->{sourceID} ne $accountID
		  && $spell->{pos}{x} == $x && $spell->{pos}{y} == $y) {
			return 1;
		}
	}
	return 0;
}

##
# objectIsMovingTowards(object1, object2, [max_variance])
#
# Check whether $object1 is moving towards $object2.
sub objectIsMovingTowards {
	my $obj = shift;
	my $obj2 = shift;
	my $max_variance = (shift || 15);

	if (!timeOut($obj->{time_move}, $obj->{time_move_calc})) {
		# $obj is still moving
		my %vec;
		getVector(\%vec, $obj->{pos_to}, $obj->{pos});
		return checkMovementDirection($obj->{pos}, \%vec, $obj2->{pos_to}, $max_variance);
	}
	return 0;
}

##
# objectIsMovingTowardsPlayer(object, [ignore_party_members = 1])
#
# Check whether an object is moving towards a player.
sub objectIsMovingTowardsPlayer {
	my $obj = shift;
	my $ignore_party_members = shift;
	$ignore_party_members = 1 if (!defined $ignore_party_members);

	if (!timeOut($obj->{time_move}, $obj->{time_move_calc}) && @playersID) {
		# Monster is still moving, and there are players on screen
		my %vec;
		getVector(\%vec, $obj->{pos_to}, $obj->{pos});

		my $players = $playersList->getItems();
		foreach my $player (@{$players}) {
			my $ID = $player->{ID};
			next if (
			     ($ignore_party_members && $char->{party} && $char->{party}{users}{$ID})
			  || (defined($player->{name}) && existsInList($config{tankersList}, $player->{name}))
			  || $player->{statuses}{"GM Perfect Hide"});
			if (checkMovementDirection($obj->{pos}, \%vec, $player->{pos}, 15)) {
				return 1;
			}
		}
	}
	return 0;
}


#########################################
#########################################
### CATEGORY: Logging
#########################################
#########################################

sub itemLog {
	my $crud = shift;
	return if (!$config{'itemHistory'});
	open ITEMLOG, ">>:utf8", $Settings::item_log_file;
	print ITEMLOG "[".getFormattedDate(int(time))."] $crud";
	close ITEMLOG;
}

sub chatLog {
	my $type = shift;
	my $message = shift;
	open CHAT, ">>:utf8", $Settings::chat_log_file;
	print CHAT "[".getFormattedDate(int(time))."][".uc($type)."] $message";
	close CHAT;
}

sub shopLog {
	my $crud = shift;
	open SHOPLOG, ">>:utf8", $Settings::shop_log_file;
	print SHOPLOG "[".getFormattedDate(int(time))."] $crud";
	close SHOPLOG;
}

sub monsterLog {
	my $crud = shift;
	return if (!$config{'monsterLog'});
	open MONLOG, ">>:utf8", $Settings::monster_log_file;
	print MONLOG "[".getFormattedDate(int(time))."] $crud\n";
	close MONLOG;
}


#########################################
#########################################
### CATEGORY: Operating system specific
#########################################
#########################################


##
# launchURL(url)
#
# Open $url in the operating system's preferred web browser.
sub launchURL {
	my $url = shift;

	if ($^O eq 'MSWin32') {
		require Utils::Win32;
		Utils::Win32::ShellExecute(0, undef, $url);

	} else {
		my $mod = 'use POSIX;';
		eval $mod;

		# This is a script I wrote for the autopackage project
		# It autodetects the current desktop environment
		my $detectionScript = <<EOF;
			function detectDesktop() {
				if [[ "\$DISPLAY" = "" ]]; then
                			return 1
				fi

				local LC_ALL=C
				local clients
				if ! clients=`xlsclients`; then
			                return 1
				fi

				if echo "\$clients" | grep -qE '(gnome-panel|nautilus|metacity)'; then
					echo gnome
				elif echo "\$clients" | grep -qE '(kicker|slicker|karamba|kwin)'; then
        			        echo kde
				else
        			        echo other
				fi
				return 0
			}
			detectDesktop
EOF

		my ($r, $w, $desktop);
		my $pid = IPC::Open2::open2($r, $w, '/bin/bash');
		print $w $detectionScript;
		close $w;
		$desktop = <$r>;
		$desktop =~ s/\n//;
		close $r;
		waitpid($pid, 0);

		sub checkCommand {
			foreach (split(/:/, $ENV{PATH})) {
				return 1 if (-x "$_/$_[0]");
			}
			return 0;
		}

		if ($desktop eq "gnome" && checkCommand('gnome-open')) {
			launchApp(1, 'gnome-open', $url);

		} elsif ($desktop eq "kde") {
			launchApp(1, 'kfmclient', 'exec', $url);

		} else {
			if (checkCommand('firefox')) {
				launchApp(1, 'firefox', $url);
			} elsif (checkCommand('mozillaa')) {
				launchApp(1, 'mozilla', $url);
			} else {
				$interface->errorDialog(TF("No suitable browser detected. Please launch your favorite browser and go to:\n%s", $url));
			}
		}
	}
}


#######################################
#######################################
### CATEGORY: Other functions
#######################################
#######################################

sub actorAddedRemovedVars {
	my ($source) = @_;
	# returns (type, list, hash)
	if ($source == $itemsList) {
		return ('item', \@itemsID, \%items);
	} elsif ($source == $playersList) {
		return ('player', \@playersID, \%players);
	} elsif ($source == $monstersList) {
		return ('monster', \@monstersID, \%monsters);
	} elsif ($source == $portalsList) {
		return ('portal', \@portalsID, \%portals);
	} elsif ($source == $petsList) {
		return ('pet', \@petsID, \%pets);
	} elsif ($source == $npcsList) {
		return ('npc', \@npcsID, \%npcs);
	} elsif ($source == $slavesList) {
		return ('slave', \@slavesID, \%slaves);
	} else {
		return (undef, undef, undef);
	}
}

sub actorAdded {
	my (undef, $source, $arg) = @_;
	my ($actor, $index) = @{$arg};

	$actor->{binID} = $index;

	my ($type, $list, $hash) = actorAddedRemovedVars ($source);

	if (defined $type) {
		if (DEBUG && scalar(keys %{$hash}) + 1 != $source->size()) {
			use Data::Dumper;

			my $ol = '';
			my $items = $source->getItems();
			foreach my $item (@{$items}) {
				$ol .= $item->nameIdx . "\n";
			}

			die "$type: " . scalar(keys %{$hash}) . " + 1 != " . $source->size() . "\n" .
				"List:\n" .
				Dumper($list) . "\n" .
				"Hash:\n" .
				Dumper($hash) . "\n" .
				"ObjectList:\n" .
				$ol;
		}
		assert(binSize($list) + 1 == $source->size()) if DEBUG;

		binAdd($list, $actor->{ID});
		$hash->{$actor->{ID}} = $actor;
		objectAdded($type, $actor->{ID}, $actor);

		assert(scalar(keys %{$hash}) == $source->size()) if DEBUG;
		assert(binSize($list) == $source->size()) if DEBUG;
	}
}

sub actorRemoved {
	my (undef, $source, $arg) = @_;
	my ($actor, $index) = @{$arg};

	my ($type, $list, $hash) = actorAddedRemovedVars ($source);

	if (defined $type) {
		if (DEBUG && scalar(keys %{$hash}) - 1 != $source->size()) {
			use Data::Dumper;

			my $ol = '';
			my $items = $source->getItems();
			foreach my $item (@{$items}) {
				$ol .= $item->nameIdx . "\n";
			}

			die "$type:" . scalar(keys %{$hash}) . " - 1 != " . $source->size() . "\n" .
				"List:\n" .
				Dumper($list) . "\n" .
				"Hash:\n" .
				Dumper($hash) . "\n" .
				"ObjectList:\n" .
				$ol;
		}
		assert(binSize($list) - 1 == $source->size()) if DEBUG;

		binRemove($list, $actor->{ID});
		delete $hash->{$actor->{ID}};
		objectRemoved($type, $actor->{ID}, $actor);

		if ($type eq "player") {
			binRemove(\@venderListsID, $actor->{ID});
			delete $venderLists{$actor->{ID}};
		}

		assert(scalar(keys %{$hash}) == $source->size()) if DEBUG;
		assert(binSize($list) == $source->size()) if DEBUG;
	}
}

sub actorListClearing {
	undef %items;
	undef %players;
	undef %monsters;
	undef %portals;
	undef %npcs;
	undef %pets;
	undef %slaves;
	undef @itemsID;
	undef @playersID;
	undef @monstersID;
	undef @portalsID;
	undef @npcsID;
	undef @petsID;
	undef @slavesID;
}

sub avoidGM_talk {
	return 0 if ($net->clientAlive() || !$config{avoidGM_talk});
	my ($user, $msg) = @_;

	# Check whether this "GM" is on the ignore list
	# in order to prevent false matches
	return 0 if (existsInList($config{avoidGM_ignoreList}, $user));

	if ($user =~ /^([a-z]?ro)?-?(Sub)?-?\[?GM\]?/i || $user =~ /$config{avoidGM_namePattern}/) {
		my %args = (
			name => $user,
		);
		Plugins::callHook('avoidGM_talk', \%args);
		return 1 if ($args{return});

		warning T("Disconnecting to avoid GM!\n");
		main::chatLog("k", TF("*** The GM %s talked to you, auto disconnected ***\n", $user));

		warning TF("Disconnect for %s seconds...\n", $config{avoidGM_reconnect});
		relog($config{avoidGM_reconnect}, 1);
		return 1;
	}
	return 0;
}

sub avoidList_talk {
	return 0 if ($net->clientAlive() || !$config{avoidList});
	my ($user, $msg, $ID) = @_;

	if ($avoid{Players}{lc($user)}{disconnect_on_chat} || $avoid{ID}{$ID}{disconnect_on_chat}) {
		warning TF("Disconnecting to avoid %s!\n", $user);
		main::chatLog("k", TF("*** %s talked to you, auto disconnected ***\n", $user));
		warning TF("Disconnect for %s seconds...\n", $config{avoidList_reconnect});
		relog($config{avoidList_reconnect}, 1);
		return 1;
	}
	return 0;
}

sub calcStat {
	my $damage = shift;
	$totaldmg += $damage;
}

##
# center(string, width, [fill])
#
# This function will center $string within a field $width characters wide,
# using $fill characters for padding on either end of the string for
# centering. If $fill is not specified, a space will be used.
sub center {
	my ($string, $width, $fill) = @_;

	$fill ||= ' ';
	my $left = int(($width - length($string)) / 2);
	my $right = ($width - length($string)) - $left;
	return $fill x $left . $string . $fill x $right;
}

# Returns: 0 if user chose to quit, 1 if user chose a character, 2 if user created or deleted a character
sub charSelectScreen {
	my %plugin_args = (autoLogin => shift);
	# A list of character names
	my @charNames;
	# An array which maps an index in @charNames to an index in @chars
	my @charNameIndices;
	my $mode;

	TOP: {
		undef $mode;
		@charNames = ();
		@charNameIndices = ();
	}

	for (my $num = 0; $num < @chars; $num++) {
		next unless ($chars[$num] && %{$chars[$num]});
		if (0) {
			# The old (more verbose) message
			swrite(
				T("-------  Character \@< ---------\n" .
				"Name: \@<<<<<<<<<<<<<<<<<<<<<<<<\n" .
				"Job:  \@<<<<<<<      Job Exp: \@<<<<<<<\n" .
				"Lv:   \@<<<<<<<      Str: \@<<<<<<<<\n" .
				"J.Lv: \@<<<<<<<      Agi: \@<<<<<<<<\n" .
				"Exp:  \@<<<<<<<      Vit: \@<<<<<<<<\n" .
				"HP:   \@||||/\@||||   Int: \@<<<<<<<<\n" .
				"SP:   \@||||/\@||||   Dex: \@<<<<<<<<\n" .
				"Zenny: \@<<<<<<<<<<  Luk: \@<<<<<<<<\n" .
				"-------------------------------"),
				$num, $chars[$num]{'name'}, $jobs_lut{$chars[$num]{'jobID'}}, $chars[$num]{'exp_job'},
				$chars[$num]{'lv'}, $chars[$num]{'str'}, $chars[$num]{'lv_job'}, $chars[$num]{'agi'},
				$chars[$num]{'exp'}, $chars[$num]{'vit'}, $chars[$num]{'hp'}, $chars[$num]{'hp_max'},
				$chars[$num]{'int'}, $chars[$num]{'sp'}, $chars[$num]{'sp_max'}, $chars[$num]{'dex'},
				$chars[$num]{'zenny'}, $chars[$num]{'luk'});
		}
		push @charNames, TF("Slot %d: %s (%s, level %d/%d)",
			$num,
			$chars[$num]{name},
			$jobs_lut{$chars[$num]{'jobID'}},
			$chars[$num]{lv},
			$chars[$num]{lv_job});
		push @charNameIndices, $num;
	}

	if (@charNames) {
		message(TF("------------- Character List -------------\n" .
		           "%s\n" .
		           "------------------------------------------\n",
		           join("\n", @charNames)),
		           "connection");
	}
	return 1 if $net->clientAlive;

	Plugins::callHook('charSelectScreen', \%plugin_args);
	return $plugin_args{return} if ($plugin_args{return});

	if ($plugin_args{autoLogin} && @chars && $config{char} ne "" && $chars[$config{char}]) {
		$messageSender->sendCharLogin($config{char});
		$timeout{charlogin}{time} = time;
		return 1;
	}

	if (@chars) {
		my @choices = @charNames;
		push @choices, (T('Create a new character'), T('Delete a character'));
		my $choice = $interface->showMenu(
			T("Please choose a character or an action."), \@choices,
			title => T("Character selection"));
		if ($choice == -1) {
			# User cancelled
			quit();
			return 0;

		} elsif ($choice < @charNames) {
			# Character chosen
			configModify('char', $charNameIndices[$choice], 1);
			$messageSender->sendCharLogin($config{char});
			$timeout{charlogin}{time} = time;
			return 1;

		} elsif ($choice == @charNames) {
			# 'Create character' chosen
			$mode = "create";

		} else {
			# 'Delete character' chosen
			$mode = "delete";
		}
	} else {
		message T("There are no characters on this account.\n"), "connection";
		$mode = "create";
	}

	if ($mode eq "create") {
		while (1) {
			my $message = T("Please enter the desired properties for your characters, in this form:\n" .
				"(slot) \"(name)\" [ (str) (agi) (vit) (int) (dex) (luk) [ (hairstyle) [(haircolor)] ] ]");
			my $input = $interface->query($message);
			if (!defined($input)) {
				goto TOP;
			} else {
				my @args = parseArgs($input);
				if (@args < 2) {
					$interface->errorDialog(T("You didn't specify enough parameters."), 0);
					next;
				}

				message TF("Creating character \"%s\" in slot \"%s\"...\n", $args[1], $args[0]), "connection";
				$timeout{charlogin}{time} = time;
				last if (createCharacter(@args));
			}
		}

	} elsif ($mode eq "delete") {
		my $choice = $interface->showMenu(
			T("Select the character you want to delete."),
			\@charNames,
			title => T("Delete character"));
		if ($choice == -1) {
			goto TOP;
		}
		my $charIndex = @charNameIndices[$choice];

		my $email = $interface->query("Enter your email address.");
		if (!defined($email)) {
			goto TOP;
		}

		my $confirmation = $interface->showMenu(
			TF("Are you ABSOLUTELY SURE you want to delete:\n%s", $charNames[$choice]),
			[T("No, don't delete"), T("Yes, delete")],
			title => T("Confirm delete"));
		if ($confirmation != 1) {
			goto TOP;
		}

		$messageSender->sendCharDelete($chars[$charIndex]{charID}, $email);
		message TF("Deleting character %s...\n", $chars[$charIndex]{name}), "connection";
		$AI::temp::delIndex = $charIndex;
		$timeout{charlogin}{time} = time;
	}
	return 2;
}

sub chatLog_clear {
	if (-f $Settings::chat_log_file) {
		unlink($Settings::chat_log_file);
	}
}

##
# checkAllowedMap($map)
#
# Checks whether $map is in $config{allowedMaps}.
# Disconnects if it is not, and $config{allowedMaps_reaction} != 0.
sub checkAllowedMap {
	my $map = shift;

	return unless $AI == 2;
	return unless $config{allowedMaps};
	return if existsInList($config{allowedMaps}, $map);
	return if $config{allowedMaps_reaction} == 0;

	warning TF("The current map (%s) is not on the list of allowed maps.\n", $map);
	main::chatLog("k", TF("** The current map (%s) is not on the list of allowed maps.\n", $map));
	main::chatLog("k", T("** Exiting...\n"));
	quit();
}

##
# checkFollowMode()
# Returns: 1 if in follow mode, 0 if not.
#
# Check whether we're current in follow mode.
sub checkFollowMode {
	my $followIndex;
	if ($config{follow} && defined($followIndex = AI::findAction("follow"))) {
		return 1 if (AI::args($followIndex)->{following});
	}
	return 0;
}

##
# boolean checkMonsterCleanness(Bytes ID)
# ID: the monster's ID.
# Requires: $ID is a valid monster ID.
#
# Checks whether a monster is "clean" (not being attacked by anyone).
sub checkMonsterCleanness {
	return 1 if (!$config{attackAuto});
	my $ID = $_[0];
	return 1 if ($playersList->getByID($ID));
	my $monster = $monstersList->getByID($ID);

	# If party attacked monster, or if monster attacked/missed party
	if ($monster->{dmgFromParty} > 0 || $monster->{dmgToParty} > 0 || $monster->{missedToParty} > 0) {
		return 1;
	}

	if ($config{aggressiveAntiKS}) {
		# Aggressive anti-KS mode, for people who are paranoid about not kill stealing.

		# If we attacked the monster first, do not drop it, we are being KSed
		return 1 if ($monster->{dmgFromYou} || $monster->{missedFromYou});
		
		# If others attacked the monster then always drop it, wether it attacked us or not!
		return 0 if (($monster->{dmgFromPlayer} && %{$monster->{dmgFromPlayer}})
			  || ($monster->{missedFromPlayer} && %{$monster->{missedFromPlayer}})
			  || (($monster->{castOnByPlayer}) && %{$monster->{castOnByPlayer}})
			  || (($monster->{castOnToPlayer}) && %{$monster->{castOnToPlayer}}));
	}
	
	# If monster attacked/missed you
	return 1 if ($monster->{'dmgToYou'} || $monster->{'missedYou'});

	# If we're in follow mode
	if (defined(my $followIndex = AI::findAction("follow"))) {
		my $following = AI::args($followIndex)->{following};
		my $followID = AI::args($followIndex)->{ID};

		if ($following) {
			# And master attacked monster, or the monster attacked/missed master
			if ($monster->{dmgToPlayer}{$followID} > 0
			 || $monster->{missedToPlayer}{$followID} > 0
			 || $monster->{dmgFromPlayer}{$followID} > 0) {
				return 1;
			}
		}
	}

	if (objectInsideSpell($monster)) {
		# Prohibit attacking this monster in the future
		$monster->{dmgFromPlayer}{$char->{ID}} = 1;
		return 0;
	}

	#check party casting on mob
	my $allowed = 1; 
	if (scalar(keys %{$monster->{castOnByPlayer}}) > 0) 
	{ 
		foreach (keys %{$monster->{castOnByPlayer}}) 
		{ 
			my $ID1=$_; 
			my $source = Actor::get($_); 
			unless ( existsInList($config{tankersList}, $source->{name}) || 
				($char->{party} && %{$char->{party}} && $char->{party}{users}{$ID1} && %{$char->{party}{users}{$ID1}})) 
			{ 
				$allowed = 0; 
				last; 
			} 
		} 
	} 

	# If monster hasn't been attacked by other players
	if (scalar(keys %{$monster->{missedFromPlayer}}) == 0
	 && scalar(keys %{$monster->{dmgFromPlayer}})    == 0
	 #&& scalar(keys %{$monster->{castOnByPlayer}})   == 0	#change to $allowed
	&& $allowed

	 # and it hasn't attacked any other player
	 && scalar(keys %{$monster->{missedToPlayer}}) == 0
	 && scalar(keys %{$monster->{dmgToPlayer}})    == 0
	 && scalar(keys %{$monster->{castOnToPlayer}}) == 0
	) {
		# The monster might be getting lured by another player.
		# So we check whether it's walking towards any other player, but only
		# if we haven't already attacked the monster.
		if ($monster->{dmgFromYou} || $monster->{missedFromYou}) {
			return 1;
		} else {
			return !objectIsMovingTowardsPlayer($monster);
		}
	}

	# The monster didn't attack you.
	# Other players attacked it, or it attacked other players.
	if ($monster->{dmgFromYou} || $monster->{missedFromYou}) {
		# If you have already attacked the monster before, then consider it clean
		return 1;
	}
	# If you haven't attacked the monster yet, it's unclean.

	return 0;
}

##
# boolean createCharacter(int slot, String name, int [str,agi,vit,int,dex,luk] = 5)
# slot: The slot in which to create the character (1st slot is 0).
# name: The name of the character to create.
# Returns: Whether the parameters are correct. Only a character creation command
#          will be sent to the server if all parameters are correct.
#
# Create a new character. You must be currently connected to the character login server.
sub createCharacter {
	my $slot = shift;
	my $name = shift;
	my ($str,$agi,$vit,$int,$dex,$luk, $hair_style, $hair_color) = @_;

	if (!@_) {
		($str,$agi,$vit,$int,$dex,$luk) = (5,5,5,5,5,5);
	}

	if ($net->getState() != 3) {
		$interface->errorDialog(T("We're not currently connected to the character login server."), 0);
		return 0;
	} elsif ($slot !~ /^\d+$/) {
		$interface->errorDialog(TF("Slot \"%s\" is not a valid number.", $slot), 0);
		return 0;
	} elsif ($slot < 0 || $slot > 4) {
		$interface->errorDialog(T("The slot must be comprised between 0 and 4."), 0);
		return 0;
	} elsif ($chars[$slot]) {
		$interface->errorDialog(TF("Slot %s already contains a character (%s).", $slot, $chars[$slot]{name}), 0);
		return 0;
	} elsif (length($name) > 23) {
		$interface->errorDialog(T("Name must not be longer than 23 characters."), 0);
		return 0;

	} else {
		for ($str,$agi,$vit,$int,$dex,$luk) {
			if ($_ > 9 || $_ < 1) {
				$interface->errorDialog(T("Stats must be comprised between 1 and 9."), 0);
				return;
			}
		}
		for ($str+$int, $agi+$luk, $vit+$dex) {
			if ($_ != 10) {
				$interface->errorDialog(T("The sums Str + Int, Agi + Luk and Vit + Dex must all be equal to 10."), 0);
				return;
			}
		}

		$messageSender->sendCharCreate($slot, $name,
			$str, $agi, $vit, $int, $dex, $luk,
			$hair_style, $hair_color);
		return 1;
	}
}

##
# void deal(Actor::Player player)
# Requires: defined($player)
# Ensures: exists $outgoingDeal{ID}
#
# Sends $player a deal request.
sub deal {
	my $player = $_[0];
	assert(defined $player) if DEBUG;
	assert(UNIVERSAL::isa($player, 'Actor::Player')) if DEBUG;

	$outgoingDeal{ID} = $player->{ID};
	$messageSender->sendDeal($player->{ID});
}

##
# dealAddItem($item, $amount)
#
# Adds $amount of $item to the current deal.
sub dealAddItem {
	my ($item, $amount) = @_;

	$messageSender->sendDealAddItem($item->{index}, $amount);
	$currentDeal{lastItemAmount} = $amount;
}

##
# drop(itemIndex, amount)
#
# Drops $amount of the item specified by $itemIndex. If $amount is not specified or too large, it defaults
# to the number of items you have.
sub drop {
	my ($itemIndex, $amount) = @_;
	my $item = $char->inventory->get($itemIndex);
	if ($item) {
		if (!$amount || $amount > $item->{amount}) {
			$amount = $item->{amount};
		}
		$messageSender->sendDrop($item->{index}, $amount);
	}
}

sub dumpData {
	my $msg = shift;
	my $silent = shift;
	my $dump;
	my $puncations = quotemeta '~!@#$%^&*()_+|\"\'';

	$dump = "\n\n================================================\n" .
		getFormattedDate(int(time)) . "\n\n" .
		length($msg) . " bytes\n\n";

	for (my $i = 0; $i < length($msg); $i += 16) {
		my $line;
		my $data = substr($msg, $i, 16);
		my $rawData = '';

		for (my $j = 0; $j < length($data); $j++) {
			my $char = substr($data, $j, 1);

			if (($char =~ /\W/ && $char =~ /\S/ && !($char =~ /[$puncations]/))
			    || ($char eq chr(10) || $char eq chr(13) || $char eq "\t")) {
				$rawData .= '.';
			} else {
				$rawData .= substr($data, $j, 1);
			}
		}

		$line = getHex(substr($data, 0, 8));
		$line .= '    ' . getHex(substr($data, 8)) if (length($data) > 8);

		$line .= ' ' x (50 - length($line)) if (length($line) < 54);
		$line .= "    $rawData\n";
		$line = sprintf("%3d>  ", $i) . $line;
		$dump .= $line;
	}

	open DUMP, ">> DUMP.txt";
	print DUMP $dump;
	close DUMP;

	debug "$dump\n", "parseMsg", 2;
	message T("Message Dumped into DUMP.txt!\n"), undef, 1 unless ($silent);
}

sub getEmotionByCommand {
	my $command = shift;
	foreach (keys %emotions_lut) {
		if (existsInList($emotions_lut{$_}{command}, $command)) {
			return $_;
		}
	}
	return undef;
}

sub getIDFromChat {
	my $r_hash = shift;
	my $msg_user = shift;
	my $match_text = shift;
	my $qm;
	if ($match_text !~ /\w+/ || $match_text eq "me" || $match_text eq "") {
		foreach (keys %{$r_hash}) {
			next if ($_ eq "");
			if ($msg_user eq $r_hash->{$_}{name}) {
				return $_;
			}
		}
	} else {
		foreach (keys %{$r_hash}) {
			next if ($_ eq "");
			$qm = quotemeta $match_text;
			if ($r_hash->{$_}{name} =~ /$qm/i) {
				return $_;
			}
		}
	}
	return undef;
}

##
# getNPCName(ID)
# ID: the packed ID of the NPC
# Returns: the name of the NPC
#
# Find the name of an NPC: could be NPC, monster, or unknown.
sub getNPCName {
	my $ID = shift;
	if ((my $npc = $npcsList->getByID($ID))) {
		return $npc->name;
	} elsif ((my $monster = $monstersList->getByID($ID))) {
		return $monster->name;
	} else {
		return "Unknown #" . unpack("V1", $ID);
	}
}

##
# getPlayerNameFromCache(player)
# player: an Actor::Player object.
# Returns: 1 on success, 0 if the player isn't in cache.
#
# Retrieve a player's name from cache and modify the player object.
sub getPlayerNameFromCache {
	my ($player) = @_;

	return if (!$config{cachePlayerNames});
	my $entry = $playerNameCache{$player->{ID}};
	return if (!$entry);

	# Check whether the cache entry is too old or inconsistent.
	# Default cache life time: 15 minutes.
	if (timeOut($entry->{time}, $config{cachePlayerNames_duration}) || $player->{lv} != $entry->{lv} || $player->{jobID} != $entry->{jobID}) {
		binRemove(\@playerNameCacheIDs, $player->{ID});
		delete $playerNameCache{$player->{ID}};
		compactArray(\@playerNameCacheIDs);
		return 0;
	}

	$player->{name} = $entry->{name};
	$player->{guild} = $entry->{guild} if ($entry->{guild});
	return 1;
}

sub getPortalDestName {
	my $ID = shift;
	my %hash; # We only want unique names, so we use a hash
	foreach (keys %{$portals_lut{$ID}{'dest'}}) {
		my $key = $portals_lut{$ID}{'dest'}{$_}{'map'};
		$hash{$key} = 1;
	}

	my @destinations = sort keys %hash;
	return join('/', @destinations);
}

sub getResponse {
	my $type = quotemeta shift;

	my @keys;
	foreach my $key (keys %responses) {
		if ($key =~ /^$type\_\d+$/) {
			push @keys, $key;
		}
	}

	my $msg = $responses{$keys[int(rand(@keys))]};
	$msg =~ s/\%\$(\w+)/$responseVars{$1}/eig;
	return $msg;
}

sub getSpellName {
	my $spell = shift;
	return $spells_lut{$spell} || "Unknown $spell";
}

##
# inInventory($itemName, $quantity = 1)
#
# Returns the item's index (can be 0!) if you have at least $quantity units of the item
# specified by $itemName in your inventory.
# Returns nothing otherwise.
sub inInventory {
	my ($itemIndex, $quantity) = @_;
	$quantity ||= 1;

	my $item = $char->inventory->getByName($itemIndex);
	return if !$item;
	return unless $item->{amount} >= $quantity;
	return $item->{invIndex};
}

##
# inventoryItemRemoved($invIndex, $amount)
#
# Removes $amount of $invIndex from $char->{inventory}.
# Also prints a message saying the item was removed (unless it is an arrow you
# fired).
sub inventoryItemRemoved {
	my ($invIndex, $amount) = @_;

	my $item = $char->inventory->get($invIndex);
	if (!$char->{arrow} || ($item && $char->{arrow} != $item->{index})) {
		# This item is not an equipped arrow
		message TF("Inventory Item Removed: %s (%d) x %d\n", $item->{name}, $invIndex, $amount), "inventory";
	}
	$item->{amount} -= $amount;
	$char->inventory->remove($item) if ($item->{amount} <= 0);
	$itemChange{$item->{name}} -= $amount;
}

# Resolve the name of a card
sub cardName {
	my $cardID = shift;

	# If card name is unknown, just return ?number
	my $card = $items_lut{$cardID};
	return "?$cardID" if !$card;
	$card =~ s/ Card$//;
	return $card;
}

# Resolve the name of a simple item
sub itemNameSimple {
	my $ID = shift;
	return 'Unknown' unless defined($ID);
	return 'None' unless $ID;
	return $items_lut{$ID} || "Unknown #$ID";
}

##
# itemName($item)
#
# Resolve the name of an item. $item should be a hash with these keys:
# nameID  => integer index into %items_lut
# cards   => 8-byte binary data as sent by server
# upgrade => integer upgrade level
sub itemName {
	my $item = shift;

	my $name = itemNameSimple($item->{nameID});

	# Resolve item prefix/suffix (carded or forged)
	my $prefix = "";
	my $suffix = "";
	my @cards;
	my %cards;
	for (my $i = 0; $i < 4; $i++) {
		my $card = unpack("v1", substr($item->{cards}, $i*2, 2));
		last unless $card;
		push(@cards, $card);
		($cards{$card} ||= 0) += 1;
	}
	if ($cards[0] == 254) {
		# Alchemist-made potion
		#
		# Ignore the "cards" inside.
	} elsif ($cards[0] == 65280) {
		# Pet egg
		# cards[0] == 65280
		# substr($item->{cards}, 2, 4) = packed pet ID
		# cards[3] == 1 if named, 0 if not named

	} elsif ($cards[0] == 255) {
		# Forged weapon
		#
		# Display e.g. "VVS Earth" or "Fire"
		my $elementID = $cards[1] % 10;
		my $elementName = $elements_lut{$elementID};
		my $starCrumbs = ($cards[1] >> 8) / 5;
		$prefix .= ('V'x$starCrumbs)."S " if $starCrumbs;
		$prefix .= "$elementName " if ($elementName ne "");
	} elsif (@cards) {
		# Carded item
		#
		# List cards in alphabetical order.
		# Stack identical cards.
		# e.g. "Hydra*2,Mummy*2", "Hydra*3,Mummy"
		$suffix = join(':', map {
			cardName($_).($cards{$_} > 1 ? "*$cards{$_}" : '')
		} sort { cardName($a) cmp cardName($b) } keys %cards);
	}

	my $numSlots = $itemSlotCount_lut{$item->{nameID}} if ($prefix eq "");

	my $display = "";
	$display .= "BROKEN " if $item->{broken};
	$display .= "+$item->{upgrade} " if $item->{upgrade};
	$display .= $prefix if $prefix;
	$display .= $name;
	$display .= " [$suffix]" if $suffix;
	$display .= " [$numSlots]" if $numSlots;

	return $display;
}

##
# storageGet(items, max)
# items: reference to an array of storage item hashes.
# max: the maximum amount to get, for each item, or 0 for unlimited.
#
# Get one or more items from storage.
#
# Example:
# # Get items $a and $b from storage.
# storageGet([$a, $b]);
# # Get items $a and $b from storage, but at most 30 of each item.
# storageGet([$a, $b], 30);
sub storageGet {
	my $indices = shift;
	my $max = shift;

	if (@{$indices} == 1) {
		my ($item) = @{$indices};
		if (!defined($max) || $max > $item->{amount}) {
			$max = $item->{amount};
		}
		$messageSender->sendStorageGet($item->{index}, $max);

	} else {
		my %args;
		$args{items} = $indices;
		$args{max} = $max;
		$args{timeout} = 0.15;
		AI::queue("storageGet", \%args);
	}
}

##
# headgearName(lookID)
#
# Resolves a lookID of a headgear into a human readable string.
#
# A lookID corresponds to a line number in tables/headgears.txt.
# The number on that line is the itemID for the headgear.
sub headgearName {
	my ($lookID) = @_;

	return "Nothing" if $lookID == 0;

	my $itemID = $headgears_lut[$lookID];

	if (!defined($itemID)) {
		return "Unknown lookID $lookID";
	}

	return main::itemName({nameID => $itemID});
}

##
# void initUserSeed()
#
# Generate a unique seed for the current user and save it to
# a file, or load the seed from that file if it exists.
sub initUserSeed {
	my $seedFile = "$Settings::logs_folder/seed.txt";
	my $f;

	if (-f $seedFile) {
		if (open($f, "<", $seedFile)) {
			binmode $f;
			$userSeed = <$f>;
			$userSeed =~ s/\n.*//s;
			close($f);
		} else {
			$userSeed = '0';
		}
	} else {
		$userSeed = '';
		for (0..10) {
			$userSeed .= rand(2 ** 49);
		}

		if (open($f, ">", $seedFile)) {
			binmode $f;
			print $f $userSeed;
			close($f);
		}
	}
}

sub itemLog_clear {
	if (-f $Settings::item_log_file) { unlink($Settings::item_log_file); }
}

##
# look(bodydir, [headdir])
# bodydir: a number 0-7. See directions.txt.
# headdir: 0 = look directly, 1 = look right, 2 = look left
#
# Look in the given directions.
sub look {
	my %args = (
		look_body => shift,
		look_head => shift
	);
	AI::queue("look", \%args);
}

##
# lookAtPosition(pos, [headdir])
# pos: a reference to a coordinate hash.
# headdir: 0 = face directly, 1 = look right, 2 = look left
#
# Turn face and body direction to position %pos.
sub lookAtPosition {
	my $pos2 = shift;
	my $headdir = shift;
	my %vec;
	my $direction;

	getVector(\%vec, $pos2, $char->{pos_to});
	$direction = int(sprintf("%.0f", (360 - vectorToDegree(\%vec)) / 45)) % 8;
	look($direction, $headdir);
}

##
# manualMove(dx, dy)
#
# Moves the character offset from its current position.
sub manualMove {
	my ($dx, $dy) = @_;

	# Stop following if necessary
	if ($config{'follow'}) {
		configModify('follow', 0);
		AI::clear('follow');
	}

	# Stop moving if necessary
	AI::clear(qw/move route mapRoute/);
	main::ai_route($field{name}, $char->{pos_to}{x} + $dx, $char->{pos_to}{y} + $dy);
}

##
# meetingPosition(ID, attackMaxDistance)
# ID: ID of the character to meet.
# attackMaxDistance: attack distance based on attack method.
#
# Returns: the position where the character should go to meet a moving monster.
sub meetingPosition {
	my ($target, $attackMaxDistance) = @_;
	my $monsterSpeed = ($target->{walk_speed}) ? 1 / $target->{walk_speed} : 0;
	my $timeMonsterMoves = time - $target->{time_move};

	my %monsterPos;
	$monsterPos{x} = $target->{pos}{x};
	$monsterPos{y} = $target->{pos}{y};
	my %monsterPosTo;
	$monsterPosTo{x} = $target->{pos_to}{x};
	$monsterPosTo{y} = $target->{pos_to}{y};

	my %realMonsterPos = calcPosFromTime(\%monsterPos, \%monsterPosTo, $monsterSpeed, $timeMonsterMoves);
	
	my $mySpeed = ($char->{walk_speed}) ? 1 / $char->{walk_speed} : 0;
	my $timeCharMoves = time - $char->{time_move};

	my %myPos;
	$myPos{x} = $char->{pos}{x};
	$myPos{y} = $char->{pos}{y};
	my %myPosTo;
	$myPosTo{x} = $char->{pos_to}{x};
	$myPosTo{y} = $char->{pos_to}{y};

	my %realMyPos = calcPosFromTime(\%myPos, \%myPosTo, $mySpeed, $timeCharMoves);

	my $timeMonsterWalks;
	my $timeCharWalks;
	my %monsterStep;
	my %charStep;
	# There can not be zero step if monster moves
	for (my $monsterStep = 1; $monsterStep <= countSteps(\%realMonsterPos, \%monsterPosTo); $monsterStep++) {
		# Calculate the steps
		%monsterStep = moveAlong(\%realMonsterPos, \%monsterPosTo, $monsterStep);

		# Calculate time to walk for monster
		$timeMonsterWalks = calcTime(\%realMonsterPos, \%monsterStep, $monsterSpeed);

		# Character's route to monsterStep position
		for (my $charStep = 0; $charStep <= countSteps(\%realMyPos, \%monsterStep); $charStep++) {
			# Calculate the steps
			%charStep = moveAlong(\%realMyPos, \%monsterStep, $charStep);

			# Check whether the distance is fine
			if (round(distance(\%charStep, \%monsterStep)) <= $attackMaxDistance) {
				# Calculate time to walk for char
				$timeCharWalks = calcTime(\%realMyPos, \%charStep, $mySpeed);

				# Check whether character comes earlier or at the same time
				if ($timeCharWalks <= $timeMonsterWalks) {
					return \%charStep;
				}
			}
		}
	}
	# If the monster is too fast, move to its pos_to plus attackMaxDistance
	for (my $charStep = 0; $charStep <= countSteps(\%realMyPos, \%monsterPosTo); $charStep++) {
		# Calculate the steps
		%charStep = moveAlong(\%realMyPos, \%monsterPosTo, $charStep);

		# Check whether the distance is fine
		if (round(distance(\%charStep, \%monsterPosTo)) <= $attackMaxDistance) {
			last;
		}
	}
	return \%charStep;
}

sub objectAdded {
	my ($type, $ID, $obj) = @_;

	if ($type eq 'player' || $type eq 'slave') {
		# Try to retrieve the player name from cache.
		if (!getPlayerNameFromCache($obj)) {
			push @unknownPlayers, $ID;
		}

	} elsif ($type eq 'npc') {
		push @unknownNPCs, $ID;
	}

	if ($type eq 'monster') {
		if (mon_control($obj->{name},$obj->{nameID})->{teleport_search}) {
			$ai_v{temp}{searchMonsters}++;
		}
	}

	Plugins::callHook('objectAdded', {
		type => $type,
		ID => $ID,
		obj => $obj
	});
}

sub objectRemoved {
	my ($type, $ID, $obj) = @_;

	if ($type eq 'monster') {
		if (mon_control($obj->{name},$obj->{nameID})->{teleport_search}) {
			$ai_v{temp}{searchMonsters}--;
		}
	}

	Plugins::callHook('objectRemoved', {
		type => $type,
		ID => $ID
	});
}

##
# items_control($name)
#
# Returns the items_control.txt settings for item name $name.
# If $name has no specific settings, use 'all'.
sub items_control {
	my ($name) = @_;

	return $items_control{lc($name)} || $items_control{all} || {};
}

##
# mon_control($name)
#
# Returns the mon_control.txt settings for monster name $name.
# If $name has no specific settings, use 'all'.
sub mon_control {
	my $name = shift;
	my $nameID = shift;
	return $mon_control{lc($name)} || $mon_control{$nameID} || $mon_control{all} || { attack_auto => 1 };
}

##
# pickupitems($name)
#
# Returns the pickupitems.txt settings for item name $name.
# If $name has no specific settings, use 'all'.
sub pickupitems {
	my ($name) = @_;

	return ($pickupitems{lc($name)} ne '') ? $pickupitems{lc($name)} : $pickupitems{all};
}

sub positionNearPlayer {
	my $r_hash = shift;
	my $dist = shift;

	my $players = $playersList->getItems();
	foreach my $player (@{$players}) {
		my $ID = $player->{ID};
		next if ($char->{party} && $char->{party}{users} &&
			$char->{party}{users}{$ID});
		next if (defined($player->{name}) && existsInList($config{tankersList}, $player->{name}));
		return 1 if (distance($r_hash, $player->{pos_to}) <= $dist);
	}
	return 0;
}

sub positionNearPortal {
	my $r_hash = shift;
	my $dist = shift;

	my $portals = $portalsList->getItems();
	foreach my $portal (@{$portals}) {
		return 1 if (distance($r_hash, $portal->{pos}) <= $dist);
	}
	return 0;
}

##
# printItemDesc(itemID)
#
# Print the description for $itemID.
sub printItemDesc {
	my $itemID = shift;
	my $itemName = itemNameSimple($itemID);
	my $description = $itemsDesc_lut{$itemID} || T("Error: No description available.\n");
	message TF("===============Item Description===============\nItem: %s\n\n", $itemName), "info";
	message($description, "info");
	message("==============================================\n", "info");
}

sub processNameRequestQueue {
	my ($queue, $actorLists, $foo) = @_;

	while (@{$queue}) {
		my $ID = $queue->[0];
		
		my $actor;
		foreach my $actorList (@$actorLists) {
			last if $actor = $actorList->getByID($ID);
		}

		# Some private servers ban you if you request info for an object with
		# GM Perfect Hide status
		if (!$actor || defined($actor->{name}) || $actor->{statuses}{"GM Perfect Hide"}) {
			shift @{$queue};
			next;
		}

		# Remove actors with a distance greater than clientSight. Some private servers (notably Freya) use
		# a technique where they send actor_exists packets with ridiculous distances in order to automatically
		# ban bots. By removingthose actors, we eliminate that possibility and emulate the client more closely.
		if (defined $actor->{pos_to} && (my $block_dist = blockDistance($char->{pos_to}, $actor->{pos_to})) >= ($config{clientSight} || 16)) {
			debug "Removed actor at $actor->{pos_to}{x} $actor->{pos_to}{y} (distance: $block_dist)\n";
			shift @{$queue};
			next;
		}

		$messageSender->sendGetPlayerInfo($ID);
		$actor = shift @{$queue};
		push @{$queue}, $actor if ($actor);
		last;
	}
}

sub quit {
	$quit = 1;
	message T("Exiting...\n"), "system";
}

sub relog {
	my $timeout = (shift || 5);
	my $silent = shift;
	$net->setState(1) if ($net);
	undef $conState_tries;
	$timeout_ex{'master'}{'time'} = time;
	$timeout_ex{'master'}{'timeout'} = $timeout;
	$net->serverDisconnect() if ($net);
	message TF("Relogging in %d seconds...\n", $timeout), "connection" unless $silent;
}

##
# sendMessage(String type, String msg, String user)
# type: Specifies what kind of message this is. "c" for public chat, "g" for guild chat,
#       "p" for party chat, "pm" for private message, "k" for messages that only the RO
#       client will see (in X-Kore mode.)
# msg: The message to send.
# user: 
#
# Send a chat message to a user.
sub sendMessage {
	my ($sender, $type, $msg, $user) = @_;
	my ($j, @msgs, $oldmsg, $amount, $space);

	@msgs = split /\\n/, $msg;
	for ($j = 0; $j < @msgs; $j++) {
		my (@msg, $i);

		@msg = split / /, $msgs[$j];
		undef $msg;
		for ($i = 0; $i < @msg; $i++) {
			if (!length($msg[$i])) {
				$msg[$i] = " ";
				$space = 1;
			}
			if (length($msg[$i]) > $config{'message_length_max'}) {
				while (length($msg[$i]) >= $config{'message_length_max'}) {
					$oldmsg = $msg;
					if (length($msg)) {
						$amount = $config{'message_length_max'};
						if ($amount - length($msg) > 0) {
							$amount = $config{'message_length_max'} - 1;
							$msg .= " " . substr($msg[$i], 0, $amount - length($msg));
						}
					} else {
						$amount = $config{'message_length_max'};
						$msg .= substr($msg[$i], 0, $amount);
					}
					if ($type eq "c") {
						$sender->sendChat($msg);
					} elsif ($type eq "g") {
						$sender->sendGuildChat($msg);
					} elsif ($type eq "p") {
						$sender->sendPartyChat($msg);
					} elsif ($type eq "pm") {
						$sender->sendPrivateMsg($user, $msg);
						%lastpm = (
							msg => $msg,
							user => $user
						);
						push @lastpm, {%lastpm};
					} elsif ($type eq "k") {
						$sender->injectMessage($msg);
	 				}
					$msg[$i] = substr($msg[$i], $amount - length($oldmsg), length($msg[$i]) - $amount - length($oldmsg));
					undef $msg;
				}
			}
			if (length($msg[$i]) && length($msg) + length($msg[$i]) <= $config{'message_length_max'}) {
				if (length($msg)) {
					if (!$space) {
						$msg .= " " . $msg[$i];
					} else {
						$space = 0;
						$msg .= $msg[$i];
					}
				} else {
					$msg .= $msg[$i];
				}
			} else {
				if ($type eq "c") {
					$sender->sendChat($msg);
				} elsif ($type eq "g") {
					$sender->sendGuildChat($msg);
				} elsif ($type eq "p") {
					$sender->sendPartyChat($msg);
				} elsif ($type eq "pm") {
					$sender->sendPrivateMsg($user, $msg);
					%lastpm = (
						msg => $msg,
						user => $user
					);
					push @lastpm, {%lastpm};
				} elsif ($type eq "k") {
					$sender->injectMessage($msg);
				}
				$msg = $msg[$i];
			}
			if (length($msg) && $i == @msg - 1) {
				if ($type eq "c") {
					$sender->sendChat($msg);
				} elsif ($type eq "g") {
					$sender->sendGuildChat($msg);
				} elsif ($type eq "p") {
					$sender->sendPartyChat($msg);
				} elsif ($type eq "pm") {
					$sender->sendPrivateMsg($user, $msg);
					%lastpm = (
						msg => $msg,
						user => $user
					);
					push @lastpm, {%lastpm};
				} elsif ($type eq "k") {
					$sender->injectMessage($msg);
				}
			}
		}
	}
}

# Keep track of when we last cast a skill
sub setSkillUseTimer {
	my ($skillID, $targetID, $wait) = @_;
	my $skill = new Skill(idn => $skillID);
	my $handle = $skill->getHandle();

	$char->{skills}{$handle}{time_used} = time;
	delete $char->{time_cast};
	delete $char->{cast_cancelled};
	$char->{last_skill_time} = time;
	$char->{last_skill_used} = $skillID;
	$char->{last_skill_target} = $targetID;

	# increment monsterSkill maxUses counter
	if (defined $targetID) {
		my $actor = Actor::get($targetID);
		$actor->{skillUses}{$skill->getHandle()}++;
	}

	# Set encore skill if applicable
	$char->{encoreSkill} = $skill if $targetID eq $accountID && $skillsEncore{$skill->getHandle()};
}

sub setPartySkillTimer {
	my ($skillID, $targetID) = @_;
	my $skill = new Skill(idn => $skillID);
	my $handle = $skill->getHandle();

	# set partySkill target_time
	my $i = $targetTimeout{$targetID}{$handle};
	$ai_v{"partySkill_${i}_target_time"}{$targetID} = time if $i ne "";
}


##
# boolean setStatus(Actor actor, param1, param2, param3)
# param1: the state information of the actor.
# param2: the ailment information of the actor.
# param3: the "look" information of the actor.
# Returns: Whether the actor should be removed from the actor list.
#
# Sets the state, ailment, and "look" statuses of the actor.
# Does not include skillsstatus.txt items.
sub setStatus {
	my ($actor, $param1, $param2, $param3) = @_;
	my $verbosity = $actor->{ID} eq $accountID ? 1 : 2;
	my $are = $actor->verb('are', 'is');
	my $have = $actor->verb('have', 'has');
	my $changed = 0;

	foreach (keys %skillsState) {
		if ($param1 == $_) {
			if (!$actor->{statuses}{$skillsState{$_}}) {
				$actor->{statuses}{$skillsState{$_}} = 1;
				message "$actor $are in $skillsState{$_} state\n", "parseMsg_statuslook", $verbosity;
				$changed = 1;
			}
		} elsif ($actor->{statuses}{$skillsState{$_}}) {
			delete $actor->{statuses}{$skillsState{$_}};
			message "$actor $are out of $skillsState{$_} state\n", "parseMsg_statuslook", $verbosity;
			$changed = 1;
		}
	}

	foreach (keys %skillsAilments) {
		if (($param2 & $_) == $_) {
			if (!$actor->{statuses}{$skillsAilments{$_}}) {
				$actor->{statuses}{$skillsAilments{$_}} = 1;
				message "$actor $have ailments: $skillsAilments{$_}\n", "parseMsg_statuslook", $verbosity;
				$changed = 1;
			}
		} elsif ($actor->{statuses}{$skillsAilments{$_}}) {
			delete $actor->{statuses}{$skillsAilments{$_}};
			message "$actor $are out of ailments: $skillsAilments{$_}\n", "parseMsg_statuslook", $verbosity;
			$changed = 1;
		}
	}

	foreach (keys %skillsLooks) {
		if (($param3 & $_) == $_) {
			if (!$actor->{statuses}{$skillsLooks{$_}}) {
				$actor->{statuses}{$skillsLooks{$_}} = 1;
				debug "$actor $have look: $skillsLooks{$_}\n", "parseMsg_statuslook", $verbosity;
				$changed = 1;
			}
		} elsif ($actor->{statuses}{$skillsLooks{$_}}) {
			delete $actor->{statuses}{$skillsLooks{$_}};
			debug "$actor $are out of look: $skillsLooks{$_}\n", "parseMsg_statuslook", $verbosity;
			$changed = 1;
		}
	}

	Plugins::callHook('changed_status',{actor => $actor, changed => $changed});

	# Remove perfectly hidden objects
	if ($actor->{statuses}{'GM Perfect Hide'}) {
		if (UNIVERSAL::isa($actor, "Actor::Player")) {
			message TF("Remove perfectly hidden %s\n", $actor);
			$playersList->remove($actor);
			# Call the hook when a perfectly hidden player is detected
			Plugins::callHook('perfect_hidden_player',undef);
			
		} elsif (UNIVERSAL::isa($actor, "Actor::Monster")) {
			message TF("Remove perfectly hidden %s\n", $actor);
			$monstersList->remove($actor);

		# NPCs do this on purpose (who knows why)
		} elsif (UNIVERSAL::isa($actor, "Actor::NPC")) {
			message "Remove perfectly hidden $actor\n";
			$npcsList->remove($actor);
		}
		return 1;
	} else {
		return 0;
	}
}


# Increment counter for monster being casted on
sub countCastOn {
	my ($sourceID, $targetID, $skillID, $x, $y) = @_;
	return unless defined $targetID;

	my $source = Actor::get($sourceID);
	my $target = Actor::get($targetID);
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;
	assert(UNIVERSAL::isa($target, 'Actor')) if DEBUG;

	if ($targetID eq $accountID) {
		$source->{castOnToYou}++;
	} elsif ($target->isa('Actor::Player')) {
		$source->{castOnToPlayer}{$targetID}++;
	} elsif ($target->isa('Actor::Monster')) {
		$source->{castOnToMonster}{$targetID}++;
	}

	if ($sourceID eq $accountID) {
		$target->{castOnByYou}++;
	} elsif ($source->isa('Actor::Player')) {
		$target->{castOnByPlayer}{$sourceID}++;
	} elsif ($source->isa('Actor::Monster')) {
		$target->{castOnByMonster}{$sourceID}++;
	}
}

sub stopAttack {
	my $pos = calcPosition($char);
	$messageSender->sendMove($pos->{x}, $pos->{y});
}

##
# boolean stripLanguageCode(String* msg)
# msg: a chat message, as sent by the RO server.
# Returns: whether the language code was stripped.
#
# Strip the language code character from a chat message.
sub stripLanguageCode {
	my $r_msg = shift;
	if ($config{chatLangCode} && $config{chatLangCode} ne "none") {
		if ($$r_msg =~ /^\|..(.*)/) {
			$$r_msg = $1;
			return 1;
		}
		return 0;
	} else {
		return 0;
	}
}

##
# void switchConf(String filename)
# filename: a configuration file.
# Returns: 1 on success, 0 if $filename does not exist.
#
# Switch to another configuration file.
sub switchConfigFile {
	my $filename = shift;
	if (! -f $filename) {
		error TF("%s does not exist.\n", $filename);
		return 0;
	}

	Settings::setConfigFilename($filename);
	parseConfigFile($filename, \%config);
	return 1;
}

sub updateDamageTables {
	my ($ID1, $ID2, $damage) = @_;

	# Track deltaHp
	#
	# A player's "deltaHp" initially starts at 0.
	# When he takes damage, the damage is subtracted from his deltaHp.
	# When he is healed, this amount is added to the deltaHp.
	# If the deltaHp becomes positive, it is reset to 0.
	#
	# Someone with a lot of negative deltaHp is probably in need of healing.
	# This allows us to intelligently heal non-party members.
	if (my $target = Actor::get($ID2)) {
		$target->{deltaHp} -= $damage;
		$target->{deltaHp} = 0 if $target->{deltaHp} > 0;
	}

	if ($ID1 eq $accountID) {
		if ((my $monster = $monstersList->getByID($ID2))) {
			# You attack monster
			$monster->{dmgTo} += $damage;
			$monster->{dmgFromYou} += $damage;
			$monster->{numAtkFromYou}++;
			if ($damage <= ($config{missDamage} || 0)) {
				$monster->{missedFromYou}++;
				debug "Incremented missedFromYou count to $monster->{missedFromYou}\n", "attackMonMiss";
				$monster->{atkMiss}++;
			} else {
				$monster->{atkMiss} = 0;
			}
			if ($config{teleportAuto_atkMiss} && $monster->{atkMiss} >= $config{teleportAuto_atkMiss}) {
				message T("Teleporting because of attack miss\n"), "teleport";
				useTeleport(1);
			}
			if ($config{teleportAuto_atkCount} && $monster->{numAtkFromYou} >= $config{teleportAuto_atkCount}) {
				message TF("Teleporting after attacking a monster %d times\n", $config{teleportAuto_atkCount}), "teleport";
				useTeleport(1);
			}

			if (AI::action eq "attack" && mon_control($monster->{name},$monster->{nameID})->{attack_auto} == 3 && $damage) {
				# Mob-training, you only need to attack the monster once to provoke it
				message TF("%s (%s) has been provoked, searching another monster\n", $monster->{name}, $monster->{binID});
				stopAttack();
				AI::dequeue();
			}


		}

	} elsif ($ID2 eq $accountID) {
		if ((my $monster = $monstersList->getByID($ID1))) {
			# Monster attacks you
			$monster->{dmgFrom} += $damage;
			$monster->{dmgToYou} += $damage;
			if ($damage == 0) {
				$monster->{missedYou}++;
			}
			$monster->{attackedYou}++ unless (
					scalar(keys %{$monster->{dmgFromPlayer}}) ||
					scalar(keys %{$monster->{dmgToPlayer}}) ||
					$monster->{missedFromPlayer} ||
					$monster->{missedToPlayer}
				);
			$monster->{target} = $ID2;

			if ($AI == 2) {
				my $teleport = 0;
				if (mon_control($monster->{name},$monster->{nameID})->{teleport_auto} == 2 && $damage){
					message TF("Teleporting due to attack from %s\n",
						$monster->{name}), "teleport";
					$teleport = 1;

				} elsif ($config{teleportAuto_deadly} && $damage >= $char->{hp}
				      && !whenStatusActive("Hallucination")) {
					message TF("Next %d dmg could kill you. Teleporting...\n",
						$damage), "teleport";
					$teleport = 1;

				} elsif ($config{teleportAuto_maxDmg} && $damage >= $config{teleportAuto_maxDmg}
				      && !whenStatusActive("Hallucination")
				      && !($config{teleportAuto_maxDmgInLock} && $field{name} eq $config{lockMap})) {
					message TF("%s hit you for more than %d dmg. Teleporting...\n",
						$monster->{name}, $config{teleportAuto_maxDmg}), "teleport";
					$teleport = 1;

				} elsif ($config{teleportAuto_maxDmgInLock} && $field{name} eq $config{lockMap}
				      && $damage >= $config{teleportAuto_maxDmgInLock}
				      && !whenStatusActive("Hallucination")) {
					message TF("%s hit you for more than %d dmg in lockMap. Teleporting...\n",
						$monster->{name}, $config{teleportAuto_maxDmgInLock}), "teleport";
					$teleport = 1;

				} elsif (AI::inQueue("sitAuto") && $config{teleportAuto_attackedWhenSitting}
				      && $damage > 0) {
					message TF("%s attacks you while you are sitting. Teleporting...\n",
						$monster->{name}), "teleport";
					$teleport = 1;

				} elsif ($config{teleportAuto_totalDmg}
				      && $monster->{dmgToYou} >= $config{teleportAuto_totalDmg}
				      && !whenStatusActive("Hallucination")
				      && !($config{teleportAuto_totalDmgInLock} && $field{name} eq $config{lockMap})) {
					message TF("%s hit you for a total of more than %d dmg. Teleporting...\n",
						$monster->{name}, $config{teleportAuto_totalDmg}), "teleport";
					$teleport = 1;

				} elsif ($config{teleportAuto_totalDmgInLock} && $field{name} eq $config{lockMap}
				      && $monster->{dmgToYou} >= $config{teleportAuto_totalDmgInLock}
				      && !whenStatusActive("Hallucination")) {
					message TF("%s hit you for a total of more than %d dmg in lockMap. Teleporting...\n",
						$monster->{name}, $config{teleportAuto_totalDmgInLock}), "teleport";
					$teleport = 1;

				} elsif ($config{teleportAuto_hp} && percent_hp($char) <= $config{teleportAuto_hp}) {
					message TF("%s hit you when your HP is too low. Teleporting...\n",
						$monster->{name}), "teleport";
					$teleport = 1;

				} elsif ($config{attackChangeTarget} && ((AI::action eq "route" && AI::action(1) eq "attack") || (AI::action eq "move" && AI::action(2) eq "attack"))
				   && AI::args->{attackID} && AI::args()->{attackID} ne $ID1) {
					my $attackTarget = Actor::get(AI::args->{attackID});
					my $attackSeq = (AI::action eq "route") ? AI::args(1) : AI::args(2);
					if (!$attackTarget->{dmgToYou} && !$attackTarget->{dmgFromYou} && distance($monster->{pos_to}, calcPosition($char)) <= $attackSeq->{attackMethod}{distance}) {
						my $ignore = 0;
						# Don't attack ignored monsters
						if ((my $control = mon_control($monster->{name},$monster->{nameID}))) {
							$ignore = 1 if ( ($control->{attack_auto} == -1)
								|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
								|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
								|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
								|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
								|| ($control->{attack_auto} == 3 && ($monster->{dmgToYou} || $monster->{missedYou} || $monster->{dmgFromYou}))
								);
						}
						if (!$ignore) {
							# Change target to closer aggressive monster
							message TF("Change target to aggressive : %s (%s)\n", $monster->name, $monster->{binID});
							stopAttack();
							AI::dequeue;
							AI::dequeue if (AI::action eq "route");
							AI::dequeue;
							attack($ID1);
						}
					}

				} elsif (AI::action eq "attack" && mon_control($monster->{name},$monster->{nameID})->{attack_auto} == 3
					&& ($monster->{dmgToYou} || $monster->{missedYou} || $monster->{dmgFromYou})) {

					# Mob-training, stop attacking the monster if it has been attacking you
					message TF("%s (%s) has been provoked, searching another monster\n", $monster->{name}, $monster->{binID});
					stopAttack();
					AI::dequeue();
				}

				useTeleport(1, undef, 1) if ($teleport);
			}
		}

	} elsif ((my $monster = $monstersList->getByID($ID1))) {
		if ((my $player = $playersList->getByID($ID2) || $slavesList->getByID($ID2))) {
			# Monster attacks player
			$monster->{dmgFrom} += $damage;
			$monster->{dmgToPlayer}{$ID2} += $damage;
			$player->{dmgFromMonster}{$ID1} += $damage;
			if ($damage == 0) {
				$monster->{missedToPlayer}{$ID2}++;
				$player->{missedFromMonster}{$ID1}++;
			}
			if (existsInList($config{tankersList}, $player->{name}) ||
			    ($char->{slaves} && %{$char->{slaves}} && $char->{slaves}{$ID2} && %{$char->{slaves}{$ID2}}) ||
			    ($char->{party} && %{$char->{party}} && $char->{party}{users}{$ID2} && %{$char->{party}{users}{$ID2}})) {
				# Monster attacks party member
				$monster->{dmgToParty} += $damage;
				$monster->{missedToParty}++ if ($damage == 0);
			}
			$monster->{target} = $ID2;
			OpenKoreMod::updateDamageTables($monster) if (defined &OpenKoreMod::updateDamageTables);

			if ($AI == 2 && ($char->{slaves} && $char->{slaves}{$ID2})) {
				my $teleport = 0;
				if (mon_control($monster->{name},$monster->{nameID})->{teleport_auto} == 2 && $damage){
					message TF("Slave teleporting due to attack from %s\n",
						$monster->{name}), "teleport";
					$teleport = 1;

				} elsif ($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_deadly'} && $damage >= $char->{slaves}{$ID2}{hp}
				      && !whenStatusActive("Hallucination")) {
					message TF("Next %d dmg could kill your slave. Teleporting...\n",
						$damage), "teleport";
					$teleport = 1;

				} elsif ($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmg'} && $damage >= $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmg'}
				      && !whenStatusActive("Hallucination")
				      && !($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmgInLock'} && $field{name} eq $config{lockMap})) {
					message TF("%s hit your slave for more than %d dmg. Teleporting...\n",
						$monster->{name}, $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmg'}), "teleport";
					$teleport = 1;

				} elsif ($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmgInLock'} && $field{name} eq $config{lockMap}
				      && $damage >= $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmgInLock'}
				      && !whenStatusActive("Hallucination")) {
					message TF("%s hit your slave for more than %d dmg in lockMap. Teleporting...\n",
						$monster->{name}, $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_maxDmgInLock'}), "teleport";
					$teleport = 1;

				} elsif ($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmg'}
				      && $monster->{dmgToPlayer}{$ID2} >= $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmg'}
				      && !whenStatusActive("Hallucination")
				      && !($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmgInLock'} && $field{name} eq $config{lockMap})) {
					message TF("%s hit your slave for a total of more than %d dmg. Teleporting...\n",
						$monster->{name}, $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmg'}), "teleport";
					$teleport = 1;

				} elsif ($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmgInLock'} && $field{name} eq $config{lockMap}
				      && $monster->{dmgToPlayer}{$ID2} >= $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmgInLock'}
				      && !whenStatusActive("Hallucination")) {
					message TF("%s hit your slave for a total of more than %d dmg in lockMap. Teleporting...\n",
						$monster->{name}, $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_totalDmgInLock'}), "teleport";
					$teleport = 1;

				} elsif ($config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_hp'} && $char->{slaves}{$ID2}{hpPercent} <= $config{$char->{slaves}{$ID2}{slave_configPrefix}.'teleportAuto_hp'}) {
					message TF("%s hit your slave when your homunculus' HP is too low. Teleporting...\n",
						$monster->{name}), "teleport";
					$teleport = 1;

				} elsif (
					$config{$char->{slaves}{$ID2}{slave_configPrefix}.'attackChangeTarget'}
					&& (
						$char->{slaves}{$ID2}->action eq 'route' && $char->{slaves}{$ID2}->action(1) eq 'attack'
						or $char->{slaves}{$ID2}->action eq 'move' && $char->{slaves}{$ID2}->action(2) eq 'attack'
					)
					&& $char->{slaves}{$ID2}->args->{attackID} && $char->{slaves}{$ID2}->args->{attackID} ne $ID1
				) {
					my $attackTarget = Actor::get($char->{slaves}{$ID2}->args->{attackID});
					my $attackSeq = ($char->{slaves}{$ID2}->action eq 'route') ? $char->{slaves}{$ID2}->args(1) : $char->{slaves}{$ID2}->args(2);
					if (!$attackTarget->{dmgToPlayer}{$ID2} && !$attackTarget->{dmgFromPlayer}{$ID2} && distance($monster->{pos_to}, calcPosition($char->{slaves}{$ID2})) <= $attackSeq->{attackMethod}{distance}) {
						my $ignore = 0;
						# Don't attack ignored monsters
						if ((my $control = mon_control($monster->{name},$monster->{nameID}))) {
							$ignore = 1 if ( ($control->{attack_auto} == -1)
								|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
								|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
								|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
								|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
								);
						}
						if (!$ignore) {
							# Change target to closer aggressive monster
							message TF("Slave change target to aggressive : %s (%s)\n", $monster->name, $monster->{binID});
							$char->{slaves}{$ID2}->slave_stopAttack();
							$char->{slaves}{$ID2}->dequeue;
							$char->{slaves}{$ID2}->dequeue if $char->{slaves}{$ID2}->action eq 'route';
							$char->{slaves}{$ID2}->dequeue;
							$char->{slaves}{$ID2}->slave_attack($ID1);
						}
					}

				}
				useTeleport(1, undef, 1) if ($teleport);
			}
		}

	} elsif ((my $player = $playersList->getByID($ID1) || $slavesList->getByID($ID1))) {
		if ((my $monster = $monstersList->getByID($ID2))) {
			# Player attacks monster
			$monster->{dmgTo} += $damage;
			$monster->{dmgFromPlayer}{$ID1} += $damage;
			$monster->{lastAttackFrom} = $ID1;
			$player->{dmgToMonster}{$ID2} += $damage;

			if ($damage == 0) {
				$monster->{missedFromPlayer}{$ID1}++;
				$player->{missedToMonster}{$ID2}++;
			}

			if (existsInList($config{tankersList}, $player->{name}) || ($char->{slaves} && $char->{slaves}{$ID1}) ||
			    ($char->{party} && %{$char->{party}} && $char->{party}{users}{$ID1} && %{$char->{party}{users}{$ID1}})) {
				$monster->{dmgFromParty} += $damage;
			}
			OpenKoreMod::updateDamageTables($monster) if (defined &OpenKoreMod::updateDamageTables);
		}
	}
}

##
# updatePlayerNameCache(player)
# player: a player actor object.
sub updatePlayerNameCache {
	my ($player) = @_;

	return if (!$config{cachePlayerNames});

	# First, cleanup the cache. Remove entries that are too old.
	# Default life time: 15 minutes
	my $changed = 1;
	for (my $i = 0; $i < @playerNameCacheIDs; $i++) {
		my $ID = $playerNameCacheIDs[$i];
		if (timeOut($playerNameCache{$ID}{time}, $config{cachePlayerNames_duration})) {
			delete $playerNameCacheIDs[$i];
			delete $playerNameCache{$ID};
			$changed = 1;
		}
	}
	compactArray(\@playerNameCacheIDs) if ($changed);

	# Resize the cache if it's still too large.
	# Default cache size: 100
	while (@playerNameCacheIDs > $config{cachePlayerNames_maxSize}) {
		my $ID = shift @playerNameCacheIDs;
		delete $playerNameCache{$ID};
	}

	# Add this player name to the cache.
	my $ID = $player->{ID};
	if (!$playerNameCache{$ID}) {
		push @playerNameCacheIDs, $ID;
		my %entry = (
			name => $player->{name},
			guild => $player->{guild},
			time => time,
			lv => $player->{lv},
			jobID => $player->{jobID}
		);
		$playerNameCache{$ID} = \%entry;
	}
}

##
# useTeleport(level)
# level: 1 to teleport to a random spot, 2 to respawn.
sub useTeleport {
	my ($use_lvl, $internal, $emergency) = @_;
		
	my %args = (
		level => $use_lvl, # 1 = Teleport, 2 = respawn
		emergency => $emergency, # Needs a fast tele
		internal => $internal # Did we call useTeleport from inside useTeleport?
	);
		
	if ($use_lvl == 2 && $config{saveMap_warpChatCommand}) {
		Plugins::callHook('teleport_sent', \%args);
		sendMessage($messageSender, "c", $config{saveMap_warpChatCommand});
		return 1;
	}

	if ($use_lvl == 1 && $config{teleportAuto_useChatCommand}) {
		Plugins::callHook('teleport_sent', \%args);
		sendMessage($messageSender, "c", $config{teleportAuto_useChatCommand});
		return 1;
	}

	# for possible recursive calls
	if (!defined $internal) {
		$internal = $config{teleportAuto_useSkill};
	}

	# look if the character has the skill
	my $sk_lvl = 0;
	if ($char->{skills}{AL_TELEPORT}) {
		$sk_lvl = $char->{skills}{AL_TELEPORT}{lv};
	}

	# only if we want to use skill ?
	return if ($char->{muted});

	if ($sk_lvl > 0 && $internal > 0 && ($use_lvl == 1 || !$config{'teleportAuto_useItemForRespawn'})) {
		# We have the teleport skill, and should use it
		my $skill = new Skill(handle => 'AL_TELEPORT');
		if ($use_lvl == 2 || $internal == 1 || ($internal == 2 && !isSafe())) {
			# Send skill use packet to appear legitimate
			# (Always send skill use packet for level 2 so that saveMap
			# autodetection works)

			if ($char->{sitting}) {
				Plugins::callHook('teleport_sent', \%args);
				main::ai_skillUse($skill->getHandle(), $use_lvl, 0, 0, $accountID);
				return 1;
			} else {
				$messageSender->sendSkillUse($skill->getIDN(), $sk_lvl, $accountID);
				undef $char->{permitSkill};
			}

			if (!$emergency && $use_lvl == 1) {
				Plugins::callHook('teleport_sent', \%args);
				$timeout{ai_teleport_retry}{time} = time;
				AI::queue('teleport');
				return 1;
			}
		}

		delete $ai_v{temp}{teleport};
		debug "Sending Teleport using Level $use_lvl\n", "useTeleport";
		if ($use_lvl == 1) {
			Plugins::callHook('teleport_sent', \%args);
			$messageSender->sendTeleport("Random");
			return 1;
		} elsif ($use_lvl == 2) {
			# check for possible skill level abuse
			message T("Using Teleport Skill Level 2 though we not have it!\n"), "useTeleport" if ($sk_lvl == 1);

			# If saveMap is not set simply use a wrong .gat.
			# eAthena servers ignore it, but this trick doesn't work
			# on official servers.
			my $telemap = "prontera.gat";
			$telemap = "$config{saveMap}.gat" if ($config{saveMap} ne "");
			Plugins::callHook('teleport_sent', \%args);
			$messageSender->sendTeleport($telemap);
			return 1;
		}
	}

	# No skill try to equip a Tele clip or something,
	# if teleportAuto_equip_* is set
	if (Actor::Item::scanConfigAndCheck('teleportAuto_equip') && ($use_lvl == 1 || !$config{'teleportAuto_useItemForRespawn'})) {
		return if AI::inQueue('teleport');
		debug "Equipping Accessory to teleport\n", "useTeleport";
		AI::queue('teleport', {lv => $use_lvl});
		if ($emergency ||
		    !$config{teleportAuto_useSkill} ||
		    $config{teleportAuto_useSkill} == 3 ||
		    $config{teleportAuto_useSkill} == 2 && isSafe()) {
			$timeout{ai_teleport_delay}{time} = 1;
		}
		Actor::Item::scanConfigAndEquip('teleportAuto_equip');
		#Commands::run('aiv');
		return 1;
	}

	# else if $internal == 0 or $sk_lvl == 0
	# try to use item

	# could lead to problems if the ItemID would be different on some servers
	# 1 Jan 2006 - instead of nameID, search for *wing in the inventory
	my $item;
	if ($use_lvl == 1) {
		$item = $char->inventory->getByName("Fly Wing");
	} elsif ($use_lvl == 2) {
		$item = $char->inventory->getByName("Butterfly Wing");
	}

	if ($item) {
		# We have Fly Wing/Butterfly Wing.
		# Don't spam the "use fly wing" packet, or we'll end up using too many wings.
		if (timeOut($timeout{ai_teleport})) {
			Plugins::callHook('teleport_sent', \%args);
			$messageSender->sendItemUse($item->{index}, $accountID);
			$timeout{ai_teleport}{time} = time;
		}
		return 1;
	}

	# no item, but skill is still available
	if ( $sk_lvl > 0 ) {
		message T("No Fly Wing or Butterfly Wing, fallback to Teleport Skill\n"), "useTeleport";
		return useTeleport($use_lvl, 1, $emergency);
	}

	if ($use_lvl == 1) {
		message T("You don't have the Teleport skill or a Fly Wing\n"), "teleport";
	} else {
		message T("You don't have the Teleport skill or a Butterfly Wing\n"), "teleport";
	}
	
	return 0;
}

##
# top10Listing(args)
# args: a 282 bytes packet representing 10 names followed by 10 ranks
#
# Returns a formatted list of [# ], Name and points
sub top10Listing {
	my ($args) = @_;
	
	my $msg = $args->{RAW_MSG};

	my @list;
	my @points;
	my $i;
	my $textList = "";
	for ($i = 0; $i < 10; $i++) {
		$list[$i] = unpack("Z24", substr($msg, 2 + (24*$i), 24));
	}	
	for ($i = 0; $i < 10; $i++) {
		$points[$i] = unpack("V1", substr($msg, 242 + ($i*4), 4));
	}	
	for ($i = 0; $i < 10; $i++) {
		$textList .= swrite("[@<] @<<<<<<<<<<<<<<<<<<<<<<<<        @>>>>>>",
			[$i+1, $list[$i], $points[$i]]);
	}
	
	return $textList;	
}

##
# whenGroundStatus(target, statuses, mine)
# target: coordinates hash
# statuses: a comma-separated list of ground effects e.g. Safety Wall,Pneuma
# mine: if true, only consider ground effects that originated from me
#
# Returns 1 if $target has one of the ground effects specified by $statuses.
sub whenGroundStatus {
	my ($pos, $statuses, $mine) = @_;

	my ($x, $y) = ($pos->{x}, $pos->{y});
	for my $ID (@spellsID) {
		my $spell;
		next unless $spell = $spells{$ID};
		next if $mine && $spell->{sourceID} ne $accountID;
		if ($x == $spell->{pos}{x} &&
		    $y == $spell->{pos}{y}) {
			return 1 if existsInList($statuses, getSpellName($spell->{type}));
		}
	}
	return 0;
}

sub whenStatusActive {
	my $statuses = shift;
	my @arr = split /\s*,\s*/, $statuses;
	foreach (@arr) {
		return 1 if exists($char->{statuses}{$_});
	}
	return 0;
}

sub whenStatusActiveMon {
	my ($monster, $statuses) = @_;
	my @arr = split /\s*,\s*/, $statuses;
	foreach (@arr) {
		return 1 if $monster->{statuses}{$_};
	}
	return 0;
}

sub whenStatusActivePL {
	my ($ID, $statuses) = @_;
	
	# Incase this method was called with empty values, send TRUE back... since the user doesnt have any statusses they want to check
	return 1 if (!$ID || !$statuses);
	return whenStatusActive($statuses) if ($ID eq $accountID);

	if (my $player = $playersList->getByID($ID)) {
		my @arr = split /\s*,\s*/, $statuses;
		foreach (@arr) {
			return 1 if $player->{statuses}{$_};
		}
	}
	if ($char->{party}{users}{$ID}{online}) {
		my @arr = split /\s*,\s*/, $statuses;
		foreach (@arr) {
			return 1 if $char->{party}{users}{$ID}{statuses}{$_};
		}
	}
	if (my $slave = $slavesList->getByID($ID)) {
		my @arr = split /\s*,\s*/, $statuses;
		foreach (@arr) {
			return 1 if $slave->{statuses}{$_};
		}
	}
	return 0;
}

sub writeStorageLog {
	my ($show_error_on_fail) = @_;
	my $f;

	if (open($f, ">:utf8", $Settings::storage_log_file)) {
		print $f TF("---------- Storage %s -----------\n", getFormattedDate(int(time)));
		for (my $i = 0; $i < @storageID; $i++) {
			next if (!$storageID[$i]);
			my $item = $storage{$storageID[$i]};

			my $display = sprintf "%2d %s x %s", $i, $item->{name}, $item->{amount};
			# Translation Comment: Mark to show not identified items
			$display .= " -- " . T("Not Identified") if !$item->{identified};
			# Translation Comment: Mark to show broken items
			$display .= " -- " . T("Broken") if $item->{broken};
			print $f "$display\n";
		}
		# Translation Comment: Storage Capacity
		print $f TF("\nCapacity: %d/%d\n", $storage{items}, $storage{items_max});
		print $f "-------------------------------\n";
		close $f;

		message T("Storage logged\n"), "success";

	} elsif ($show_error_on_fail) {
		error TF("Unable to write to %s\n", $Settings::storage_log_file);
	}
}

##
# getBestTarget(possibleTargets, nonLOSNotAllowed)
# possibleTargets: reference to an array of monsters' IDs
# nonLOSNotAllowed: if set, non-LOS monsters (and monsters that aren't in attackMaxDistance) aren't checked up
#
# Returns ID of the best target
sub getBestTarget {
	my ($possibleTargets, $nonLOSNotAllowed) = @_;
	if (!$possibleTargets) {
		return;
	}

	my $portalDist = $config{'attackMinPortalDistance'} || 4;
	my $playerDist = $config{'attackMinPlayerDistance'} || 1;

	my @noLOSMonsters;
	my $myPos = calcPosition($char);
	my ($highestPri, $smallestDist, $bestTarget);

	# First of all we check monsters in LOS, then the rest of monsters

	foreach (@{$possibleTargets}) {
		my $monster = $monsters{$_};
		my $pos = calcPosition($monster);
		next if (positionNearPlayer($pos, $playerDist)
			|| positionNearPortal($pos, $portalDist)
		);
		if ((my $control = mon_control($monster->{name},$monster->{nameID}))) {
			next if ( ($control->{attack_auto} == -1)
				|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
				|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
				|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
				|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
				|| ($control->{attack_auto} == 3 && ($monster->{dmgToYou} || $monster->{missedYou} || $monster->{dmgFromYou}))
				|| ($control->{attack_auto} == 0 && !($monster->{dmgToYou} || $monster->{missedYou}))
			);
		}
		if ($config{'attackCanSnipe'}) {
			if (!checkLineSnipable($myPos, $pos)) {
				push(@noLOSMonsters, $_);
				next;
			}
		} else {
			if (!checkLineWalkable($myPos, $pos)) {
				push(@noLOSMonsters, $_);
				next;
			}
		}
		my $name = lc $monster->{name};
		my $dist = round(distance($myPos, $pos));
		
		# COMMENTED (FIX THIS): attackMaxDistance should never be used as indication of LOS
		#     The objective of attackMaxDistance is to determine the range of normal attack,
		#     and not the range of character's ability to engage monsters
		## Monsters that aren't in attackMaxDistance are not checked up
		##if ($nonLOSNotAllowed && ($config{'attackMaxDistance'} < $dist)) {
		##	next;
		##}
		if (!defined($highestPri) || ($priority{$name} > $highestPri)) {
			$highestPri = $priority{$name};
			$smallestDist = $dist;
			$bestTarget = $_;
		}
		if ((!defined($highestPri) || $priority{$name} == $highestPri)
		  && (!defined($smallestDist) || $dist < $smallestDist)) {
			$highestPri = $priority{$name};
			$smallestDist = $dist;
			$bestTarget = $_;
		}
	}
	if (!$nonLOSNotAllowed && !$bestTarget && scalar(@noLOSMonsters) > 0) {
		foreach (@noLOSMonsters) {
			# The most optimal solution is to include the path lenghts' comparison, however it will take
			# more time and CPU resources, so, we use rough solution with priority and distance comparison

			my $monster = $monsters{$_};
			my $pos = calcPosition($monster);
			my $name = lc $monster->{name};
			my $dist = round(distance($myPos, $pos));
			if (!defined($highestPri) || ($priority{$name} > $highestPri)) {
				$highestPri = $priority{$name};
				$smallestDist = $dist;
				$bestTarget = $_;
			}
			if ((!defined($highestPri) || $priority{$name} == $highestPri)
			  && (!defined($smallestDist) || $dist < $smallestDist)) {
				$highestPri = $priority{$name};
				$smallestDist = $dist;
				$bestTarget = $_;
			}
		}
	}
	return $bestTarget;
}

##
# Returns 1 if there is a player nearby (except party and homunculus) or 0 if not
sub isSafe {
	foreach (@playersID) {
		if (!$char->{party}{users}{$_} && (!$char->{homunculus} || $_ ne $char->{homunculus}{ID})) {
			return 0;
		}
	}
	return 1;
}

#######################################
#######################################
###CATEGORY: Actor's Actions Text
#######################################
#######################################

##
# String attack_string(Actor source, Actor target, int damage, int delay)
#
# Generates a proper message string for when actor $source attacks actor $target.
sub attack_string {
	my ($source, $target, $damage, $delay) = @_;
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;
	assert(UNIVERSAL::isa($target, 'Actor')) if DEBUG;

	return TF("%s %s %s - Dmg: %s (delay %s)\n",
		$source->nameString,
		$source->verb('attack', 'attacks'),
		$target->nameString($source),
		$damage, $delay);
}

sub skillCast_string {
	my ($source, $target, $x, $y, $skillName, $delay) = @_;
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;
	assert(UNIVERSAL::isa($target, 'Actor')) if DEBUG;

	# Location
	if ($x != 0 || $y != 0) {
		if ($source->isa('Actor::You')) {
			return TF("You are casting %s on location (%d, %d) - (time %sms)\n", $skillName, $x, $y, $delay);
		} elsif ($source->isa('Actor::Player')) {
			return TF("Player %s (%d) is casting %s on location (%d, %d) - (time %sms)\n", $source->name, 
				$source->{binID}, $skillName, $x, $y, $delay);
		} elsif ($source->isa('Actor::Monster')) {
			return TF("Monster %s (%d) is casting %s on location (%d, %d) - (time %sms)\n", $source->name, 
				$source->{binID}, $skillName, $x, $y, $delay);
		} elsif ($source->isa('Actor::Slave')) {
			return TF("Slave %s (%d) is casting %s on location (%d, %d) - (time %sms)\n", $source->name, 
				$source->{binID}, $skillName, $x, $y, $delay);
		} elsif ($source->isa('Actor::Unknown')) {
			return TF("Unknown #%s (%d) is casting %s on location (%d, %d) - (time %sms)\n", $source->{nameID},	
				$source->{binID}, $skillName, $x, $y, $delay);
		}

	# You
	} elsif ($source->isa('Actor::You')) {
		if ($target->isa('Actor::You')) {
			return TF("You are casting %s on yourself (time %sms)\n", $skillName, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("You are casting %s on player %s (%d) (time %sms)\n", $skillName,
				$target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("You are casting %s on monster %s (%d) (time %sms)\n", $skillName,
				$target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("You are casting %s on slave %s (%d) (time %sms)\n", $skillName,
				$target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("You are casting %s on Unknown #%s (%d) (time %sms)\n", $skillName,
				$target->{nameID}, $target->{binID}, $delay);
		}
	# Player
	} elsif ($source->isa('Actor::Player')) {
		if ($target->isa('Actor::You')) {
			return TF("Player %s (%d) is casting %s on you (time %sms)\n", $source->name, $source->{binID},
				$skillName, $delay);
		} elsif ($target->isa('Actor::Player')) {
			# consider gender
			if ($source ne $target) {
				return TF("Player %s (%d) is casting %s on player %s (%d) (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
			} elsif ($source->{sex}) {
				return TF("Player %s (%d) is casting %s on himself (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $delay);
			} else {
				return TF("Player %s (%d) is casting %s on herself (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $delay);
			}
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Player %s (%d) is casting %s on monster %s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Player %s (%d) is casting %s on slave %s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Player %s (%d) is casting %s on Unknown #%s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $delay);
		}
	# Monster
	} elsif ($source->isa('Actor::Monster')) {
		if ($target->isa('Actor::You')) {
			return TF("Monster %s (%d) is casting %s on you (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Monster %s (%d) is casting %s on player %s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			if ($source ne $target) {
				return TF("Monster %s (%d) is casting %s on monster %s (%d) (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
			} else {
				return TF("Monster %s (%d) is casting %s on itself (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $delay);
			}
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Monster %s (%d) is casting %s on slave %s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Monster %s (%d) is casting %s on Unknown #%s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $delay);
		}
	# Slave
	} elsif ($source->isa('Actor::Slave')) {
		if ($target->isa('Actor::You')) {
			return TF("Slave %s (%d) is casting %s on you (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Slave %s (%d) is casting %s on player %s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Slave %s (%d) is casting %s on monster %s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			if ($source ne $target) {
				return TF("Slave %s (%d) is casting %s on slave %s (%d) (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
			} else {
				return TF("Slave %s (%d) is casting %s on itself (time %sms)\n", $source->name,
					$source->{binID}, $skillName, $delay);
			}
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Slave %s (%d) is casting %s on Unknown #%s (%d) (time %sms)\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $delay);
		}
	# Unknown
	} elsif ($source->isa('Actor::Unknown')) {
		if ($target->isa('Actor::You')) {
			return TF("Unknown #%s (%d) is casting %s on you (time %sms)\n", $source->{nameID},
				$source->{binID}, $skillName, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Unknown #%s (%d) is casting %s on player %s (%d) (time %sms)\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Unknown #%s (%d) is casting %s on monster %s (%d) (time %sms)\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Unknown #%s (%d) is casting %s on slave %s (%d) (time %sms)\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			if ($source ne $target) {
				return TF("Unknown #%s (%d) is casting %s on Unknown #%s (%d) (time %sms)\n", $source->{nameID},
					$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $delay);
			} else {
				return TF("Unknown #%s (%d) is casting %s on himself (time %sms)\n", $source->{nameID},
					$source->{binID}, $skillName, $delay);
			}
		}
	}
}

sub skillUse_string {
	my ($source, $target, $skillName, $damage, $level, $delay) = @_;
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;
	assert(UNIVERSAL::isa($target, 'Actor')) if DEBUG;

	$damage ||= "Miss!";
	if ($damage != -30000) {
		# Translation Comment: Ammount of Damage on Skill
		$damage = "- " . TF("Dmg: %s", $damage) . " ";
	} else {
		$damage = '';
	}

	# Translation Comment: Skill name + level
	$skillName = TF("%s (lvl %s)", $skillName, $level) unless $level == 65535;

	# You
	if ($source->isa('Actor::You')) {
		if ($target->isa('Actor::You')) {
			return TF("You use %s on yourself %s(delay %s)\n", $skillName, $damage, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("You use %s on player %s (%d) %s(delay %s)\n", $skillName,
				$target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("You use %s on monster %s (%d) %s(delay %s)\n", $skillName,
				$target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("You use %s on slave %s (%d) %s(delay %s)\n", $skillName,
				$target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("You use %s on Unknown #%s (%d) %s(delay %s)\n", $skillName,
				$target->{nameID}, $target->{binID}, $damage, $delay);
		}
	# Player
	} elsif ($source->isa('Actor::Player')) {
		if ($target->isa('Actor::You')) {
			return TF("Player %s (%d) uses %s on you %s(delay %s)\n", $source->name, $source->{binID},
				$skillName, $damage, $delay);
		} elsif ($target->isa('Actor::Player')) {
			# consider gender
			if ($source ne $target) {
				return TF("Player %s (%d) uses %s on player %s (%d) %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
			} elsif ($source->{sex}) {
				return TF("Player %s (%d) uses %s on himself %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $damage, $delay);
			} else {
				return TF("Player %s (%d) uses %s on herself %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $damage, $delay);
			}
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Player %s (%d) uses %s on monster %s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Player %s (%d) uses %s on slave %s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Player %s (%d) uses %s on Unknown #%s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $damage, $delay);
		}
	# Monster
	} elsif ($source->isa('Actor::Monster')) {
		if ($target->isa('Actor::You')) {
			return TF("Monster %s (%d) uses %s on you %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $damage, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Monster %s (%d) uses %s on player %s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			if ($source ne $target) {
				return TF("Monster %s (%d) uses %s on monster %s (%d) %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
			} else {
				return TF("Monster %s (%d) uses %s on itself %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $damage, $delay);
			}
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Monster %s (%d) uses %s on slave %s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Monster %s (%d) uses %s on Unknown #%s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $damage, $delay);
		}
	# Slave
	} elsif ($source->isa('Actor::Slave')) {
		if ($target->isa('Actor::You')) {
			return TF("Slave %s (%d) uses %s on you %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $damage, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Slave %s (%d) uses %s on player %s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Slave %s (%d) uses %s on monster %s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			if ($source ne $target) {
				return TF("Slave %s (%d) uses %s on slave %s (%d) %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
			} else {
				return TF("Slave %s (%d) uses %s on itself %s(delay %s)\n", $source->name,
					$source->{binID}, $skillName, $damage, $delay);
			}
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Slave %s (%d) uses %s on Unknown #%s (%d) %s(delay %s)\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $damage, $delay);
		}
	# Unknown
	} elsif ($source->isa('Actor::Unknown')) {
		message "test2\n";
		if ($target->isa('Actor::You')) {
			return TF("Unknown #%s (%d) uses %s on you %s(delay %s)\n", $source->{nameID},
				$source->{binID}, $skillName, $damage, $delay);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Unknown #%s (%d) uses %s on player %s (%d) %s(delay %s)\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Unknown #%s (%d) uses %s on monster %s (%d) %s(delay %s)\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Unknown #%s (%d) uses %s on slave %s (%d) %s(delay %s)\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $damage, $delay);
		} elsif ($target->isa('Actor::Unknown')) {
			if ($source ne $target) {
				return TF("Unknown #%s (%d) uses %s on Unknown #%s (%d) %s(delay %s)\n", $source->{nameID},
					$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $damage, $delay);
			} else {
				return TF("Unknown #%s (%d) uses %s on himself %s(delay %s)\n", $source->{nameID},
					$source->{binID}, $skillName, $damage, $delay);
			}
		}
	}
}

sub skillUseLocation_string {
	my ($source, $skillName, $args) = @_;
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;

	# Translation Comment: Skill name + level
	$skillName = TF("%s (lvl %s)", $skillName, $args->{lv}) unless $args->{lv} == 65535;

	if ($source->isa('Actor::You')) {
		return TF("You use %s on location (%d, %d)\n", $skillName, $args->{x}, $args->{y});
	} elsif ($source->isa('Actor::Player')) {
		return TF("Player %s (%d) uses %s on location (%d, %d)\n", $source->name,
			$source->{binID}, $skillName, $args->{x}, $args->{y});
	} elsif ($source->isa('Actor::Monster')) {
		return TF("Monster %s (%d) uses %s on location (%d, %d)\n", $source->name,
			$source->{binID}, $skillName, $args->{x}, $args->{y});
	} elsif ($source->isa('Actor::Slave')) {
		return TF("Slave %s (%d) uses %s on location (%d, %d)\n", $source->name,
			$source->{binID}, $skillName, $args->{x}, $args->{y});
	} elsif ($source->isa('Actor::Unknown')) {
		return TF("Unknown #%s (%d) uses %s on location (%d, %d)\n", $source->{nameID},
			$source->{binID}, $skillName, $args->{x}, $args->{y});
	}
}

sub skillUseNoDamage_string {
	my ($source, $target, $skillID, $skillName, $amount) = @_;
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;
	assert(UNIVERSAL::isa($target, 'Actor')) if DEBUG;

	if ($skillID == 28) {
		# Translation Comment: used Healing skill
		$amount = ': ' . TF("%s hp gained", $amount);
	} else {
		if ($amount) {
			# Translation Comment: used non-Healing skill - displays skill level
			$amount = ': ' . TF("Lv %s", $amount);
		} else {
			$amount = '';
		}
	}

	if ($source->isa('Actor::You')) {
		if ($target->isa('Actor::You')) {
			return TF("You use %s on yourself %s\n", $skillName, $amount);
		} else {
			# Translation Comment: You use a certain skill on an actor.
			return TF("You use %s on %s %s\n", $skillName, $target->nameString, $amount);
		}
	# Player
	} elsif ($source->isa('Actor::Player')) {
		if ($target->isa('Actor::You')) {
			return TF("Player %s uses %s on you %s\n", $source->name,
				$skillName, $amount);
		} elsif ($target->isa('Actor::Player')) {
			# consider gender
			if ($source ne $target) {
				return TF("Player %s (%d) uses %s on player %s (%d) %s\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
			} elsif ($source->{sex}) {
				return TF("Player %s (%d) uses %s on himself %s\n", $source->name,
					$source->{binID}, $skillName, $amount);
			} else {
				return TF("Player %s (%d) uses %s on herself %s\n", $source->name,
					$source->{binID}, $skillName, $amount);
			}
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Player %s (%d) uses %s on monster %s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Player %s (%d) uses %s on slave %s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Player %s (%d) uses %s on Unknown #%s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $amount);
		}
	# Monster
	} elsif ($source->isa('Actor::Monster')) {
		if ($target->isa('Actor::You')) {
			return TF("Monster %s (%d) uses %s on you %s\n", $source->name,
				$source->{binID}, $skillName, $amount);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Monster %s (%d) uses %s on player %s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Monster')) {
			if ($source ne $target) {
				return TF("Monster %s (%d) uses %s on monster %s (%d) %s\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
			} else {
				return TF("Monster %s (%d) uses %s on itself %s\n", $source->name,
					$source->{binID}, $skillName, $amount);
			}
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Monster %s (%d) uses %s on slave %s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Monster %s (%d) uses %s on Unknown #%s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $amount);
		}
	# Slave
	} elsif ($source->isa('Actor::Slave')) {
		if ($target->isa('Actor::You')) {
			return TF("Slave %s (%d) uses %s on you %s\n", $source->name,
				$source->{binID}, $skillName, $amount);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Slave %s (%d) uses %s on player %s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Slave %s (%d) uses %s on monster %s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Slave')) {
			if ($source ne $target) {
				return TF("Slave %s (%d) uses %s on slave %s (%d) %s\n", $source->name,
					$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
			} else {
				return TF("Slave %s (%d) uses %s on itself %s\n", $source->name,
					$source->{binID}, $skillName, $amount);
			}
		} elsif ($target->isa('Actor::Unknown')) {
			return TF("Slave %s (%d) uses %s on Unknown #%s (%d) %s\n", $source->name,
				$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $amount);
		}
	# Unknown
	} elsif ($source->isa('Actor::Unknown')) {
		if ($target->isa('Actor::You')) {
			return TF("Unknown #%s (%d) uses %s on you %s\n", $source->{nameID},
				$source->{binID}, $skillName, $amount);
		} elsif ($target->isa('Actor::Player')) {
			return TF("Unknown #%s (%d) uses %s on player %s (%d) %s\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Monster')) {
			return TF("Unknown #%s (%d) uses %s on monster %s (%d) %s\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Slave')) {
			return TF("Unknown #%s (%d) uses %s on slave %s (%d) %s\n", $source->{nameID},
				$source->{binID}, $skillName, $target->name, $target->{binID}, $amount);
		} elsif ($target->isa('Actor::Unknown')) {
			if ($source ne $target) {
				return TF("Unknown #%s (%d) uses %s on Unknown #%s (%d) %s\n", $source->{nameID},
					$source->{binID}, $skillName, $target->{nameID}, $target->{binID}, $amount);
			} else {
				return TF("Unknown #%s (%d) uses %s on himself %s\n", $source->{nameID},
					$source->{binID}, $skillName, $amount);
			}
		}
	}
}

sub status_string {
	my ($source, $statusName, $mode, $seconds) = @_;
	assert(UNIVERSAL::isa($source, 'Actor')) if DEBUG;

	if ($mode eq 'now') {
		if ($source->isa('Actor::You')) {
			if (($seconds)&&($seconds > 0)) {
				return TF("You are now: %s for: %s seconds.\n", $statusName, $seconds || "N/A");
			} else {
				return TF("You are now: %s\n", $statusName);
			}
		} elsif ($source->isa('Actor::Player')) {
			return TF("Player %s (%d) is now: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Monster')) {
			return TF("Monster %s (%d) is now: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Slave')) {
			return TF("Slave %s (%d) is now: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Unknown')) {
			return TF("Unknown #%s (%d) is now: %s\n", $source->{nameID}, $source->{binID}, $statusName);
		}
	} elsif ($mode eq 'again') {
		if ($source->isa('Actor::You')) {
			if (($seconds)&&($seconds > 0)) {
				return TF("You are again: %s for: %s seconds.\n", $statusName, $seconds || "N/A");
			} else {
				return TF("You are again: %s\n", $statusName);
			}
		} elsif ($source->isa('Actor::Player')) {
			return TF("Player %s (%d) is again: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Monster')) {
			return TF("Monster %s (%d) is again: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Slave')) {
			return TF("Slave %s (%d) is again: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Unknown')) {
			return TF("Unknown #%s (%d) is again: %s\n", $source->{nameID}, $source->{binID}, $statusName);
		}
	} elsif ($mode eq 'no longer') {
		if ($source->isa('Actor::You')) {
			return TF("You are no longer: %s\n", $statusName);
		} elsif ($source->isa('Actor::Player')) {
			return TF("Player %s (%d) is no longer: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Monster')) {
			return TF("Monster %s (%d) is no longer: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Slave')) {
			return TF("Slave %s (%d) is no longer: %s\n", $source->name, $source->{binID}, $statusName);
		} elsif ($source->isa('Actor::Unknown')) {
			return TF("Unknown #%s (%d) is no longer: %s\n", $source->{nameID}, $source->{binID}, $statusName);
		}
	}
}

#######################################
#######################################
###CATEGORY: AI Math
#######################################
#######################################

sub lineIntersection {
	my $r_pos1 = shift;
	my $r_pos2 = shift;
	my $r_pos3 = shift;
	my $r_pos4 = shift;
	my ($x1, $x2, $x3, $x4, $y1, $y2, $y3, $y4, $result, $result1, $result2);
	$x1 = $$r_pos1{'x'};
	$y1 = $$r_pos1{'y'};
	$x2 = $$r_pos2{'x'};
	$y2 = $$r_pos2{'y'};
	$x3 = $$r_pos3{'x'};
	$y3 = $$r_pos3{'y'};
	$x4 = $$r_pos4{'x'};
	$y4 = $$r_pos4{'y'};
	$result1 = ($x4 - $x3)*($y1 - $y3) - ($y4 - $y3)*($x1 - $x3);
	$result2 = ($y4 - $y3)*($x2 - $x1) - ($x4 - $x3)*($y2 - $y1);
	if ($result2 != 0) {
		$result = $result1 / $result2;
	}
	return $result;
}

sub percent_hp {
	my $r_hash = shift;
	if (!$$r_hash{'hp_max'}) {
		return 0;
	} else {
		return ($$r_hash{'hp'} / $$r_hash{'hp_max'} * 100);
	}
}

sub percent_sp {
	my $r_hash = shift;
	if (!$$r_hash{'sp_max'}) {
		return 0;
	} else {
		return ($$r_hash{'sp'} / $$r_hash{'sp_max'} * 100);
	}
}

sub percent_weight {
	my $r_hash = shift;
	if (!$$r_hash{'weight_max'}) {
		return 0;
	} else {
		return ($$r_hash{'weight'} / $$r_hash{'weight_max'} * 100);
	}
}


#######################################
#######################################
###CATEGORY: Misc Functions
#######################################
#######################################

sub avoidGM_near {
	my $players = $playersList->getItems();
	foreach my $player (@{$players}) {
		# skip this person if we dont know the name
		next if (!defined $player->{name});

		# Check whether this "GM" is on the ignore list
		# in order to prevent false matches
		last if (existsInList($config{avoidGM_ignoreList}, $player->{name}));

		# check if this name matches the GM filter
		last unless ($config{avoidGM_namePattern} ? $player->{name} =~ /$config{avoidGM_namePattern}/ : $player->{name} =~ /^([a-z]?ro)?-?(Sub)?-?\[?GM\]?/i);

		my %args = (
			name => $player->{name},
			ID => $player->{ID}
		);
		Plugins::callHook('avoidGM_near', \%args);
		return 1 if ($args{return});

		my $msg;
		if ($config{avoidGM_near} == 1) {
			# Mode 1: teleport & disconnect
			useTeleport(1);
			$msg = TF("GM %s is nearby, teleport & disconnect for %d seconds", $player->{name}, $config{avoidGM_reconnect});
			relog($config{avoidGM_reconnect}, 1);

		} elsif ($config{avoidGM_near} == 2) {
			# Mode 2: disconnect
			$msg = TF("GM %s is nearby, disconnect for %s seconds", $player->{name}, $config{avoidGM_reconnect});
			relog($config{avoidGM_reconnect}, 1);

		} elsif ($config{avoidGM_near} == 3) {
			# Mode 3: teleport
			useTeleport(1);
			$msg = TF("GM %s is nearby, teleporting", $player->{name});

		} elsif ($config{avoidGM_near} >= 4) {
			# Mode 4: respawn
			useTeleport(2);
			$msg = TF("GM %s is nearby, respawning", $player->{name});
		}

		warning "$msg\n";
		chatLog("k", "*** $msg ***\n");

		return 1;
	}
	return 0;
}

##
# avoidList_near()
# Returns: 1 if someone was detected, 0 if no one was detected.
#
# Checks if any of the surrounding players are on the avoid.txt avoid list.
# Disconnects / teleports if a player is detected.
sub avoidList_near {
	return if ($config{avoidList_inLockOnly} && $field{name} ne $config{lockMap});

	my $players = $playersList->getItems();
	foreach my $player (@{$players}) {
		my $avoidPlayer = $avoid{Players}{lc($player->{name})};
		my $avoidID = $avoid{ID}{$player->{nameID}};
		if (!$net->clientAlive() && ( ($avoidPlayer && $avoidPlayer->{disconnect_on_sight}) || ($avoidID && $avoidID->{disconnect_on_sight}) )) {
			warning TF("%s (%s) is nearby, disconnecting...\n", $player->{name}, $player->{nameID});
			chatLog("k", TF("*** Found %s (%s) nearby and disconnected ***\n", $player->{name}, $player->{nameID}));
			warning TF("Disconnect for %s seconds...\n", $config{avoidList_reconnect});
			relog($config{avoidList_reconnect}, 1);
			return 1;

		} elsif (($avoidPlayer && $avoidPlayer->{teleport_on_sight}) || ($avoidID && $avoidID->{teleport_on_sight})) {
			message TF("Teleporting to avoid player %s (%s)\n", $player->{name}, $player->{nameID}), "teleport";
			chatLog("k", TF("*** Found %s (%s) nearby and teleported ***\n", $player->{name}, $player->{nameID}));
			useTeleport(1);
			return 1;
		}
	}
	return 0;
}

sub avoidList_ID {
	return if (!($config{avoidList}) || ($config{avoidList_inLockOnly} && $field{name} ne $config{lockMap}));

	my $avoidID = unpack("V", shift);
	if ($avoid{ID}{$avoidID} && $avoid{ID}{$avoidID}{disconnect_on_sight}) {
		warning TF("%s is nearby, disconnecting...\n", $avoidID);
		chatLog("k", TF("*** Found %s nearby and disconnected ***\n", $avoidID));
		warning TF("Disconnect for %s seconds...\n", $config{avoidList_reconnect});
		relog($config{avoidList_reconnect}, 1);
		return 1;
	}
	return 0;
}

sub compilePortals {
	my $checkOnly = shift;

	my %mapPortals;
	my %mapSpawns;
	my %missingMap;
	my $pathfinding;
	my @solution;
	my $field;

	# Collect portal source and destination coordinates per map
	foreach my $portal (keys %portals_lut) {
		$mapPortals{$portals_lut{$portal}{source}{map}}{$portal}{x} = $portals_lut{$portal}{source}{x};
		$mapPortals{$portals_lut{$portal}{source}{map}}{$portal}{y} = $portals_lut{$portal}{source}{y};
		foreach my $dest (keys %{$portals_lut{$portal}{dest}}) {
			next if $portals_lut{$portal}{dest}{$dest}{map} eq '';
			$mapSpawns{$portals_lut{$portal}{dest}{$dest}{map}}{$dest}{x} = $portals_lut{$portal}{dest}{$dest}{x};
			$mapSpawns{$portals_lut{$portal}{dest}{$dest}{map}}{$dest}{y} = $portals_lut{$portal}{dest}{$dest}{y};
		}
	}

	$pathfinding = new PathFinding if (!$checkOnly);

	# Calculate LOS values from each spawn point per map to other portals on same map
	foreach my $map (sort keys %mapSpawns) {
		message TF("Processing map %s...\n", $map), "system" unless $checkOnly;
		foreach my $spawn (keys %{$mapSpawns{$map}}) {
			foreach my $portal (keys %{$mapPortals{$map}}) {
				next if $spawn eq $portal;
				next if $portals_los{$spawn}{$portal} ne '';
				return 1 if $checkOnly;
				if ((!$field || $field->{name} ne $map) && !$missingMap{$map}) {
					eval {
						$field = new Field(name => $map);
					};
					if ($@) {
						$missingMap{$map} = 1;
					}
				}

				my %start = %{$mapSpawns{$map}{$spawn}};
				my %dest = %{$mapPortals{$map}{$portal}};
				closestWalkableSpot($field, \%start);
				closestWalkableSpot($field, \%dest);

				$pathfinding->reset(
					start => \%start,
					dest  => \%dest,
					field => $field
					);
				my $count = $pathfinding->runcount;
				$portals_los{$spawn}{$portal} = ($count >= 0) ? $count : 0;
				debug "LOS in $map from $start{x},$start{y} to $dest{x},$dest{y}: $portals_los{$spawn}{$portal}\n";
			}
		}
	}
	return 0 if $checkOnly;

	# Write new portalsLOS.txt
	writePortalsLOS(Settings::getTableFilename("portalsLOS.txt"), \%portals_los);
	message TF("Wrote portals Line of Sight table to '%s'\n", Settings::getTableFilename("portalsLOS.txt")), "system";

	# Print warning for missing fields
	if (%missingMap) {
		warning TF("----------------------------Error Summary----------------------------\n");
		warning TF("Missing: %s.fld\n", $_) foreach (sort keys %missingMap);
		warning TF("Note: LOS information for the above listed map(s) will be inaccurate;\n" .
			"      however it is safe to ignore if those map(s) are not used\n");
		warning TF("----------------------------Error Summary----------------------------\n");
	}
}

sub compilePortals_check {
	return compilePortals(1);
}

sub portalExists {
	my ($map, $r_pos) = @_;
	foreach (keys %portals_lut) {
		if ($portals_lut{$_}{source}{map} eq $map
		    && $portals_lut{$_}{source}{x} == $r_pos->{x}
		    && $portals_lut{$_}{source}{y} == $r_pos->{y}) {
			return $_;
		}
	}
	return;
}

sub portalExists2 {
	my ($src, $src_pos, $dest, $dest_pos) = @_;
	my $srcx = $src_pos->{x};
	my $srcy = $src_pos->{y};
	my $destx = $dest_pos->{x};
	my $desty = $dest_pos->{y};
	my $destID = "$dest $destx $desty";

	foreach (keys %portals_lut) {
		my $entry = $portals_lut{$_};
		if ($entry->{source}{map} eq $src
		 && $entry->{source}{pos}{x} == $srcx
		 && $entry->{source}{pos}{y} == $srcy
		 && $entry->{dest}{$destID}) {
			return $_;
		}
	}
	return;
}

sub redirectXKoreMessages {
	my ($type, $domain, $level, $globalVerbosity, $message, $user_data) = @_;

	return if ($config{'XKore_silent'} || $type eq "debug" || $level > 0 || $net->getState() != Network::IN_GAME || $XKore_dontRedirect);
	return if ($domain =~ /^(connection|startup|pm|publicchat|guildchat|guildnotice|selfchat|emotion|drop|inventory|deal|storage|input)$/);
	return if ($domain =~ /^(attack|skill|list|info|partychat|npc|route)/);

	$message =~ s/\n*$//s;
	$message =~ s/\n/\\n/g;
	sendMessage($messageSender, "k", $message);
}

sub monKilled {
	$monkilltime = time();
	# if someone kills it
	if (($monstarttime == 0) || ($monkilltime < $monstarttime)) {
		$monstarttime = 0;
		$monkilltime = 0;
	}
	$elasped = $monkilltime - $monstarttime;
	$totalelasped = $totalelasped + $elasped;
	if ($totalelasped == 0) {
		$dmgpsec = 0
	} else {
		$dmgpsec = $totaldmg / $totalelasped;
	}
}

# Resolves a player or monster ID into a name
# Obsoleted by Actor module, don't use this!
sub getActorName {
	my $id = shift;

	if (!$id) {
		return 'Nothing';
	} else {
		my $hash = Actor::get($id);
		return $hash->nameString;
	}
}

# Resolves a pair of player/monster IDs into names
sub getActorNames {
	my ($sourceID, $targetID, $verb1, $verb2) = @_;

	my $source = getActorName($sourceID);
	my $verb = $source eq 'You' ? $verb1 : $verb2;
	my $target;

	if ($targetID eq $sourceID) {
		if ($targetID eq $accountID) {
			$target = 'yourself';
		} else {
			$target = 'self';
		}
	} else {
		$target = getActorName($targetID);
	}

	return ($source, $verb, $target);
}

# return ID based on name if party member is online
sub findPartyUserID {
	if ($char->{party} && %{$char->{party}}) {
		my $partyUserName = shift;
		for (my $j = 0; $j < @partyUsersID; $j++) {
	        	next if ($partyUsersID[$j] eq "");
			if ($partyUserName eq $char->{party}{users}{$partyUsersID[$j]}{name}
				&& $char->{party}{users}{$partyUsersID[$j]}{online}) {
				return $partyUsersID[$j];
			}
		}
	}

	return undef;
}

# fill in a hash of NPC information either based on location ("map x y")
sub getNPCInfo {
	my $id = shift;
	my $return_hash = shift;

	undef %{$return_hash};

	my ($map, $x, $y) = split(/ +/, $id, 3);

	$$return_hash{map} = $map;
	$$return_hash{pos}{x} = $x;
	$$return_hash{pos}{y} = $y;

	if (($$return_hash{map} ne "") && ($$return_hash{pos}{x} ne "") && ($$return_hash{pos}{y} ne "")) {
		$$return_hash{ok} = 1;
	} else {
		error TF("Invalid NPC information for autoBuy, autoSell or autoStorage! (%s)\n", $id);
	}
}

sub checkSelfCondition {
	my $prefix = shift;
	return 0 if (!$prefix);
	return 0 if ($config{$prefix . "_disabled"});

	return 0 if $config{$prefix."_whenIdle"} && !AI::isIdle();

	# *_manualAI 0 = auto only
	# *_manualAI 1 = manual only
	# *_manualAI 2 = auto or manual
     if ($config{$prefix . "_manualAI"} == 0 || !(defined $config{$prefix . "_manualAI"})) {
		return 0 if ($AI != 2);
	}elsif ($config{$prefix . "_manualAI"} == 1){
          return 0 if ($AI != 1);
 	}else {
          return 0 if ($AI == 0);
	}

	if ($config{$prefix . "_hp"}) {
		if ($config{$prefix."_hp"} =~ /^(.*)\%$/) {
			return 0 if (!inRange($char->hp_percent, $1));
		} else {
			return 0 if (!inRange($char->{hp}, $config{$prefix."_hp"}));
		}
	}

	if ($config{$prefix."_sp"}) {
		if ($config{$prefix."_sp"} =~ /^(.*)\%$/) {
			return 0 if (!inRange($char->sp_percent, $1));
		} else {
			return 0 if (!inRange($char->{sp}, $config{$prefix."_sp"}));
		}
	}

	if ($config{$prefix."_homunculus"} =~ /\S/) {
		return 0 if (!!$config{$prefix."_homunculus"}) ^ ($char->{homunculus} && !$char->{homunculus}{state});
	}

	if ($char->{homunculus}) {
		if ($config{$prefix . "_homunculus_hp"}) {
			if ($config{$prefix."_homunculus_hp"} =~ /^(.*)\%$/) {
				return 0 if (!inRange($char->{homunculus}{hpPercent}, $1));
			} else {
				return 0 if (!inRange($char->{homunculus}{hp}, $config{$prefix."_homunculus_hp"}));
			}
		}

		if ($config{$prefix."_homunculus_sp"}) {
			if ($config{$prefix."_homunculus_sp"} =~ /^(.*)\%$/) {
				return 0 if (!inRange($char->{homunculus}{spPercent}, $1));
			} else {
				return 0 if (!inRange($char->{homunculus}{sp}, $config{$prefix."_homunculus_sp"}));
			}
		}

		if ($config{$prefix."_homunculus_dead"}) {
			return 0 unless ($char->{homunculus}{state} & 4);
		}
	}

	if ($config{$prefix."_mercenary"} =~ /\S/) {
		return 0 if (!!$config{$prefix."_mercenary"}) ^ (!!$char->{mercenary});
	}

	if ($char->{mercenary}) {
		if ($config{$prefix . "_mercenary_hp"}) {
			if ($config{$prefix."_mercenary_hp"} =~ /^(.*)\%$/) {
				return 0 if (!inRange($char->{mercenary}{hpPercent}, $1));
			} else {
				return 0 if (!inRange($char->{mercenary}{hp}, $config{$prefix."_mercenary_hp"}));
			}
		}

		if ($config{$prefix."_mercenary_sp"}) {
			if ($config{$prefix."_mercenary_sp"} =~ /^(.*)\%$/) {
				return 0 if (!inRange($char->{mercenary}{spPercent}, $1));
			} else {
				return 0 if (!inRange($char->{mercenary}{sp}, $config{$prefix."_mercenary_sp"}));
			}
		}
		
		if ($config{$prefix . "_mercenary_whenStatusActive"}) { return 0 unless (whenStatusActivePL($char->{mercenary}, $config{$prefix . "_mercenary_whenStatusActive"})); }
		if ($config{$prefix . "_mercenary_whenStatusInactive"}) { return 0 if (whenStatusActivePL($char->{mercenary}, $config{$prefix . "_mercenary_whenStatusInactive"})); }
	}

	# check skill use SP if this is a 'use skill' condition
	if ($prefix =~ /skill/i) {
		my $skill_handle = Skill->new(name => lc($config{$prefix}))->getHandle();
		return 0 unless (($char->{skills}{$skill_handle} && $char->{skills}{$skill_handle}{lv} >= 1)
						|| ($char->{permitSkill} && $char->{permitSkill}->getName() eq $config{$prefix})
						|| $config{$prefix."_equip_leftAccessory"}
						|| $config{$prefix."_equip_rightAccessory"}
						|| $config{$prefix."_equip_leftHand"}
						|| $config{$prefix."_equip_rightHand"}
						|| $config{$prefix."_equip_robe"}
						);
		return 0 unless ($char->{sp} >= $skillsSP_lut{$skill_handle}{$config{$prefix . "_lvl"}});
	}

	if (defined $config{$prefix . "_aggressives"}) {
		return 0 unless (inRange(scalar ai_getAggressives(), $config{$prefix . "_aggressives"}));
	}

	if (defined $config{$prefix . "_partyAggressives"}) {
		return 0 unless (inRange(scalar ai_getAggressives(undef, 1), $config{$prefix . "_partyAggressives"}));
	}

	if ($config{$prefix . "_stopWhenHit"} > 0) { return 0 if (scalar ai_getMonstersAttacking($accountID)); }

	if ($config{$prefix . "_whenFollowing"} && $config{follow}) {
		return 0 if (!checkFollowMode());
	}

	if ($config{$prefix . "_whenStatusActive"}) { return 0 unless (whenStatusActive($config{$prefix . "_whenStatusActive"})); }
	if ($config{$prefix . "_whenStatusInactive"}) { return 0 if (whenStatusActive($config{$prefix . "_whenStatusInactive"})); }

	if ($config{$prefix . "_onAction"}) { return 0 unless (existsInList($config{$prefix . "_onAction"}, AI::action())); }
	if ($config{$prefix . "_notOnAction"}) { return 0 if (existsInList($config{$prefix . "_notOnAction"}, AI::action())); }
	if ($config{$prefix . "_spirit"}) {return 0 unless (inRange($char->{spirits}, $config{$prefix . "_spirit"})); }

	if ($config{$prefix . "_timeout"}) { return 0 unless timeOut($ai_v{$prefix . "_time"}, $config{$prefix . "_timeout"}) }
	if ($config{$prefix . "_inLockOnly"} > 0) { return 0 unless ($field{name} eq $config{lockMap}); }
	if ($config{$prefix . "_notWhileSitting"} > 0) { return 0 if ($char->{sitting}); }
	if ($config{$prefix . "_notInTown"} > 0) { return 0 if ($cities_lut{$field{name}.'.rsw'}); }

	if ($config{$prefix . "_monsters"} && !($prefix =~ /skillSlot/i) && !($prefix =~ /ComboSlot/i)) {
		my $exists;
		foreach (ai_getAggressives()) {
			if (existsInList($config{$prefix . "_monsters"}, $monsters{$_}->name)) {
				$exists = 1;
				last;
			}
		}
		return 0 unless $exists;
	}

	if ($config{$prefix . "_defendMonsters"}) {
		my $exists;
		foreach (ai_getMonstersAttacking($accountID)) {
			if (existsInList($config{$prefix . "_defendMonsters"}, $monsters{$_}->name)) {
				$exists = 1;
				last;
			}
		}
		return 0 unless $exists;
	}

	if ($config{$prefix . "_notMonsters"} && !($prefix =~ /skillSlot/i) && !($prefix =~ /ComboSlot/i)) {
		my $exists;
		foreach (ai_getAggressives()) {
			if (existsInList($config{$prefix . "_notMonsters"}, $monsters{$_}->name)) {
				return 0;
			}
		}
	}

	if ($config{$prefix."_inInventory"}) {
		foreach my $input (split / *, */, $config{$prefix."_inInventory"}) {
			my ($itemName, $count) = $input =~ /(.*?)(?:\s+([><]=? *\d+))?$/;
			$count = '>0' if $count eq '';
			my $item = $char->inventory->getByName($itemName);
 			return 0 if !inRange(!$item ? 0 : $item->{amount}, $count);
		}
	}

	if ($config{$prefix."_inCart"}) {
		foreach my $input (split / *, */, $config{$prefix."_inCart"}) {
			my ($item,$count) = $input =~ /(.*?)(?:\s+([><]=? *\d+))?$/;
			$count = '>0' if $count eq '';
			my $iX = findIndexString_lc($cart{inventory}, "name", $item);
 			my $item = $cart{inventory}[$iX];
			return 0 if !inRange(!defined $iX ? 0 : $item->{amount}, $count);
		}
	}

	if ($config{$prefix."_whenGround"}) {
		return 0 unless whenGroundStatus(calcPosition($char), $config{$prefix."_whenGround"});
	}

	if ($config{$prefix."_whenNotGround"}) {
		return 0 if whenGroundStatus(calcPosition($char), $config{$prefix."_whenNotGround"});
	}

	if ($config{$prefix."_whenPermitSkill"}) {
		return 0 unless $char->{permitSkill} &&
			$char->{permitSkill}->getName() eq $config{$prefix."_whenPermitSkill"};
	}

	if ($config{$prefix."_whenNotPermitSkill"}) {
		return 0 if $char->{permitSkill} &&
			$char->{permitSkill}->getName() eq $config{$prefix."_whenNotPermitSkill"};
	}

	if ($config{$prefix."_whenFlag"}) {
		return 0 unless $flags{$config{$prefix."_whenFlag"}};
	}
	if ($config{$prefix."_whenNotFlag"}) {
		return 0 unless !$flags{$config{$prefix."_whenNotFlag"}};
	}

	if ($config{$prefix."_onlyWhenSafe"}) {
		return 0 if !isSafe();
	}

	if ($config{$prefix."_inMap"}) {
		return 0 unless (existsInList($config{$prefix . "_inMap"}, $field{name}));
	}

	if ($config{$prefix."_notInMap"}) {
		return 0 if (existsInList($config{$prefix . "_notInMap"}, $field{name}));
	}

	if ($config{$prefix."_whenEquipped"}) {
		my $item = Actor::Item::get($config{$prefix."_whenEquipped"});
		return 0 unless $item && $item->{equipped};
	}

	if ($config{$prefix."_whenNotEquipped"}) {
		my $item = Actor::Item::get($config{$prefix."_whenNotEquipped"});
		return 0 if $item && $item->{equipped};
	}

	if ($config{$prefix."_zeny"}) {
		return 0 if (!inRange($char->{zenny}, $config{$prefix."_zeny"}));
	}

	# not working yet
	if ($config{$prefix."_whenWater"}) {
		my $pos = calcPosition($char);
		return 0 if ($field->getBlock($pos->{x}, $pos->{y}) != Field::WALKABLE_WATER);
	}

	my %hookArgs;
	$hookArgs{prefix} = $prefix;
	$hookArgs{return} = 1;
	Plugins::callHook("checkSelfCondition", \%hookArgs);
	return 0 if (!$hookArgs{return});

	return 1;
}

sub checkPlayerCondition {
	my ($prefix, $id) = @_;
	return 0 if (!$id);
	
	my $player = $playersList->getByID($id) || $slavesList->getByID($id);

	if ($config{$prefix . "_timeout"}) { return 0 unless timeOut($ai_v{$prefix . "_time"}{$id}, $config{$prefix . "_timeout"}) }
	if ($config{$prefix . "_whenStatusActive"}) { return 0 unless (whenStatusActivePL($id, $config{$prefix . "_whenStatusActive"})); }
	if ($config{$prefix . "_whenStatusInactive"}) { return 0 if (whenStatusActivePL($id, $config{$prefix . "_whenStatusInactive"})); }
	if ($config{$prefix . "_notWhileSitting"} > 0) { return 0 if ($player->{sitting}); }

	# we will have player HP info (only) if we are in the same party
	if ($char->{party} && $char->{party}{users}{$id}) {
		if ($config{$prefix . "_hp"}) {
			if ($config{$prefix."_hp"} =~ /^(.*)\%$/) {
				return 0 if (!inRange(percent_hp($char->{party}{users}{$id}), $1));
			} else {
				return 0 if (!inRange($char->{party}{users}{$id}{hp}, $config{$prefix . "_hp"}));
			}
		}
	} elsif ($char->{homunculus} && $char->{homunculus}{ID} eq $id) {
		if ($config{$prefix . "_hp"}) {
			if ($config{$prefix."_hp"} =~ /^(.*)\%$/) {
				return 0 if (!inRange(percent_hp($char->{homunculus}), $1));
			} else {
				return 0 if (!inRange($char->{homunculus}{hp}, $config{$prefix . "_hp"}));
			}
		}
	}

	if ($config{$prefix."_deltaHp"}){
		return 0 unless inRange($player->{deltaHp}, $config{$prefix."_deltaHp"});
	}

	# check player job class
	if ($config{$prefix . "_isJob"}) { return 0 unless (existsInList($config{$prefix . "_isJob"}, $jobs_lut{$player->{jobID}})); }
	if ($config{$prefix . "_isNotJob"}) { return 0 if (existsInList($config{$prefix . "_isNotJob"}, $jobs_lut{$player->{jobID}})); }

	if ($config{$prefix . "_aggressives"}) {
		return 0 unless (inRange(scalar ai_getPlayerAggressives($id), $config{$prefix . "_aggressives"}));
	}

	if ($config{$prefix . "_defendMonsters"}) {
		my $exists;
		foreach (ai_getMonstersAttacking($id)) {
			if (existsInList($config{$prefix . "_defendMonsters"}, $monsters{$_}{name})) {
				$exists = 1;
				last;
			}
		}
		return 0 unless $exists;
	}

	if ($config{$prefix . "_monsters"}) {
		my $exists;
		foreach (ai_getPlayerAggressives($id)) {
			if (existsInList($config{$prefix . "_monsters"}, $monsters{$_}{name})) {
				$exists = 1;
				last;
			}
		}
		return 0 unless $exists;
	}

	if ($config{$prefix."_whenGround"}) {
		return 0 unless whenGroundStatus(calcPosition($player), $config{$prefix."_whenGround"});
	}
	if ($config{$prefix."_whenNotGround"}) {
		return 0 if whenGroundStatus(calcPosition($player), $config{$prefix."_whenNotGround"});
	}
	if ($config{$prefix."_dead"}) {
		return 0 if !$player->{dead};
	} else {
		return 0 if $player->{dead};
	}

	if ($config{$prefix."_whenWeaponEquipped"}) {
		return 0 unless $player->{weapon};
	}

	if ($config{$prefix."_whenShieldEquipped"}) {
		return 0 unless $player->{shield};
	}

	if ($config{$prefix."_isGuild"}) {
		return 0 unless ($player->{guild} && existsInList($config{$prefix . "_isGuild"}, $player->{guild}{name}));
	}

	if ($config{$prefix."_dist"}) {
		return 0 unless inRange(distance(calcPosition($char), calcPosition($player)), $config{$prefix."_dist"});
	}

	my %args = (
		player => $player,
		prefix => $prefix,
		return => 1
	);

	Plugins::callHook('checkPlayerCondition', \%args);

	return $args{return};
}

sub checkMonsterCondition {
	my ($prefix, $monster) = @_;

	if ($config{$prefix . "_timeout"}) { return 0 unless timeOut($ai_v{$prefix . "_time"}{$monster->{ID}}, $config{$prefix . "_timeout"}) }

	if (my $misses = $config{$prefix . "_misses"}) {
		return 0 unless inRange($monster->{atkMiss}, $misses);
	}

	if (my $misses = $config{$prefix . "_totalMisses"}) {
		return 0 unless inRange($monster->{missedFromYou}, $misses);
	}

	if ($config{$prefix . "_whenStatusActive"}) {
		return 0 unless (whenStatusActiveMon($monster, $config{$prefix . "_whenStatusActive"}));
	}
	if ($config{$prefix . "_whenStatusInactive"}) {
		return 0 if (whenStatusActiveMon($monster, $config{$prefix . "_whenStatusInactive"}));
	}

	if ($config{$prefix."_whenGround"}) {
		return 0 unless whenGroundStatus(calcPosition($monster), $config{$prefix."_whenGround"});
	}
	if ($config{$prefix."_whenNotGround"}) {
		return 0 if whenGroundStatus(calcPosition($monster), $config{$prefix."_whenNotGround"});
	}

	if ($config{$prefix."_dist"}) {
		return 0 unless inRange(distance(calcPosition($char), calcPosition($monster)), $config{$prefix."_dist"});
	}

	if ($config{$prefix."_deltaHp"}){
		return 0 unless inRange($monster->{deltaHp}, $config{$prefix."_deltaHp"});
	}

	# This is only supposed to make sense for players,
	# but it has to be here for attackSkillSlot PVP to work
	if ($config{$prefix."_whenWeaponEquipped"}) {
		return 0 unless $monster->{weapon};
	}
	if ($config{$prefix."_whenShieldEquipped"}) {
		return 0 unless $monster->{shield};
	}

	my %args = (
		monster => $monster,
		prefix => $prefix,
		return => 1
	);

	Plugins::callHook('checkMonsterCondition', \%args);
	return $args{return};
}

##
# findCartItemInit()
#
# Resets all "found" flags in the cart to 0.
sub findCartItemInit {
	for (@{$cart{inventory}}) {
		next unless $_ && %{$_};
		undef $_->{found};
	}
}

##
# findCartItem($name [, $found [, $nounid]])
#
# Returns the integer index into $cart{inventory} for the cart item matching
# the given name, or undef.
#
# If an item is found, the "found" value for that item is set to 1. Items
# cannot be found again until you reset the "found" flags using
# findCartItemInit(), if $found is true.
#
# Unidentified items will not be returned if $nounid is true.
sub findCartItem {
	my ($name, $found, $nounid) = @_;

	$name = lc($name);
	my $index = 0;
	for (@{$cart{inventory}}) {
		if (lc($_->{name}) eq $name &&
		    !($found && $_->{found}) &&
			!($nounid && !$_->{identified})) {
			$_->{found} = 1;
			return $index;
		}
		$index++;
	}
	return undef;
}

##
# makeShop()
#
# Returns an array of items to sell. The array can be no larger than the
# maximum number of items that the character can vend. Each item is a hash
# reference containing the keys "index", "amount" and "price".
#
# If there is a problem with opening a shop, an error message will be printed
# and nothing will be returned.
sub makeShop {
	if ($shopstarted) {
		error T("A shop has already been opened.\n");
		return;
	}

	return unless $char;

	if (!$char->{skills}{MC_VENDING}{lv}) {
		error T("You don't have the Vending skill.\n");
		return;
	}

	if (!$shop{title_line}) {
		error T("Your shop does not have a title.\n");
		return;
	}

	my @items = ();
	my $max_items = $char->{skills}{MC_VENDING}{lv} + 2;

	# Iterate through items to be sold
	findCartItemInit();
	shuffleArray(\@{$shop{items}}) if ($config{'shop_random'} eq "2");
	for my $sale (@{$shop{items}}) {
		my $index = findCartItem($sale->{name}, 1, 1);
		next unless defined($index);

		# Found item to vend
		my $cart_item = $cart{inventory}[$index];
		my $amount = $cart_item->{amount};

		my %item;
		$item{name} = $cart_item->{name};
		$item{index} = $index;
		$item{price} = $sale->{price};
		$item{amount} =
			$sale->{amount} && $sale->{amount} < $amount ?
			$sale->{amount} : $amount;
		push(@items, \%item);

		# We can't vend anymore items
		last if @items >= $max_items;
	}

	if (!@items) {
		error T("There are no items to sell.\n");
		return;
	}
	shuffleArray(\@items) if ($config{'shop_random'} eq "1");
	return @items;
}

sub openShop {
	my @items = makeShop();
	my @shopnames;
	return unless @items;
	@shopnames = split(/;;/, $shop{title_line});
	$shop{title} = $shopnames[int rand($#shopnames + 1)];
	$shop{title} = ($config{shopTitleOversize}) ? $shop{title} : substr($shop{title},0,36);
	$messageSender->sendOpenShop($shop{title}, \@items);
	message TF("Shop opened (%s) with %d selling items.\n", $shop{title}, @items.""), "success";
	$shopstarted = 1;
	$shopEarned = 0;
}

sub closeShop {
	if (!$shopstarted) {
		error T("A shop has not been opened.\n");
		return;
	}

	$messageSender->sendCloseShop();

	$shopstarted = 0;
	$timeout{'ai_shop'}{'time'} = time;
	message T("Shop closed.\n");
}

##
# inLockMap()
#
# Returns 1 (true) if character is located in its lockmap.
# Returns 0 (false) if character is not located in lockmap.
sub inLockMap {
	if ($field{'name'} eq $config{'lockMap'}) {
		return 1;
	} else {
		return 0;
	}
}

sub parseReload {
	my ($args) = @_;
	eval {
		my $progressHandler = sub {
			my ($filename) = @_;
			message TF("Loading %s...\n", $filename);
		};
		if ($args eq 'all') {
			Settings::loadAll($progressHandler);
		} else {
			Settings::loadByRegexp(qr/$args/, $progressHandler);
		}
		Log::initLogFiles();
	};
	if (my $e = caught('UTF8MalformedException')) {
		error TF(
			"The file %s must be valid UTF-8 encoded, which it is \n" .
			"currently not. To solve this prolem, please use Notepad\n" .
			"to save that file as valid UTF-8.",
			$e->textfile);
	} elsif ($@) {
		die $@;
	}
}

sub MODINIT {
	OpenKoreMod::initMisc() if (defined(&OpenKoreMod::initMisc));
}

return 1;
