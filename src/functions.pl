#########################################################################
# This software is open source, licensed under the GNU General Public
# License, version 2.
# Basically, this means that you're allowed to modify and distribute
# this software. However, if you distribute modified versions, you MUST
# also distribute the source code.
# See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################

package main;
use strict;
use Time::HiRes qw(time usleep);
use IO::Socket;
use Text::ParseWords;
use Carp::Assert;
use Data::YAML::Writer;
use Config;
use encoding 'utf8';

use Globals;
use Modules;
use Settings qw(%sys);
use Log qw(message warning error debug);
use Interface;
use Network::Receive;
use Network::Send ();
use Network::PaddedPackets;
use Network::MessageTokenizer;
use Commands;
use Misc;
use Plugins;
use Utils;
use ChatQueue;
use I18N;
use Utils::Benchmark;
use Utils::HttpReader;


#######################################
# PROGRAM INITIALIZATION
#######################################

use constant {
	STATE_LOAD_PLUGINS          => 0,
	STATE_LOAD_DATA_FILES       => 1,
	STATE_INIT_NETWORKING       => 2,
	STATE_INIT_PORTALS_DATABASE => 3,
	STATE_PROMPT                => 4,
	STATE_FINAL_INIT            => 5,
	STATE_INITIALIZED           => 6
};

our $state;

sub mainLoop {
	Benchmark::begin('mainLoop') if DEBUG;
	$state = STATE_LOAD_PLUGINS if (!defined $state);

	# Parse command input
	my $input;
	if (defined($input = $interface->getInput(0))) {
		Misc::checkValidity("parseInput (pre)");
		parseInput($input);
		Misc::checkValidity("parseInput");
	}


	if ($state == STATE_INITIALIZED) {
		Plugins::callHook('mainLoop_pre');
		mainLoop_initialized();
		Plugins::callHook('mainLoop_post');

	} elsif ($state == STATE_LOAD_PLUGINS) {
		Log::message("$Settings::versionText\n");
		loadPlugins();
		Log::message("\n");
		Plugins::callHook('start');
		$state = STATE_LOAD_DATA_FILES;

	} elsif ($state == STATE_LOAD_DATA_FILES) {
		loadDataFiles();
		$state = STATE_INIT_NETWORKING;

	} elsif ($state == STATE_INIT_NETWORKING) {
		initNetworking();
		$state = STATE_INIT_PORTALS_DATABASE;

	} elsif ($state == STATE_INIT_PORTALS_DATABASE) {
		initPortalsDatabase();
		$state = STATE_PROMPT;

	} elsif ($state == STATE_PROMPT) {
		promptFirstTimeInformation();
		$state = STATE_FINAL_INIT;

	} elsif ($state == STATE_FINAL_INIT) {
		finalInitialization();
		$state = STATE_INITIALIZED;

	} else {
		die "Unknown state $state.";
	}

	Benchmark::end('mainLoop') if DEBUG;
	# Reload any modules that requested to be reloaded
	Modules::reloadAllInQueue();
}

sub loadPlugins {
	eval {
		Plugins::loadAll();
	};
	if (my $e = caught('Plugin::LoadException')) {
		$interface->errorDialog(TF("This plugin cannot be loaded because of a problem in the plugin. " .
			"Please notify the plugin's author about this problem, " .
			"or remove the plugin so %s can start.\n\n" .
			"The error message is:\n" .
			"%s",
			$Settings::NAME, $e->message));
		exit 1;
	} elsif (my $e = caught('Plugin::DeniedException')) {
		$interface->errorDialog($e->message);
		exit 1;
	} elsif ($@) {
		die $@;
	}
}

sub loadDataFiles {
	# These pragmas are necessary in order to support non-ASCII filenames.
	# If we use UTF-8 strings then Perl will think the file doesn't exist,
	# if $Settings::control_folder or $Settings::tables_folder contains
	# non-ASCII characters.
	no encoding 'utf8';

	Settings::addControlFile(Settings::getConfigFilename(),
		loader => [\&parseConfigFile, \%config],
		autoSearch => 0);
	Settings::addControlFile(Settings::getMonControlFilename(),
		loader => [\&parseMonControl, \%mon_control],
		autoSearch => 0);
	Settings::addControlFile(Settings::getItemsControlFilename(),
		loader => [\&parseItemsControl, \%items_control],
		autoSearch => 0);
	Settings::addControlFile(Settings::getShopFilename(),
		loader => [\&parseShopControl, \%shop],
		autoSearch => 0);
	Settings::addControlFile('overallAuth.txt', loader => [\&parseDataFile, \%overallAuth]);
	Settings::addControlFile('pickupitems.txt', loader => [\&parseDataFile_lc, \%pickupitems]);
	Settings::addControlFile('responses.txt',   loader => [\&parseResponses, \%responses]);
	Settings::addControlFile('timeouts.txt',    loader => [\&parseTimeouts, \%timeout]);
	Settings::addControlFile('chat_resp.txt',   loader => [\&parseChatResp, \@chatResponses]);
	Settings::addControlFile('avoid.txt',       loader => [\&parseAvoidControl, \%avoid]);
	Settings::addControlFile('priority.txt',    loader => [\&parsePriority, \%priority]);
	Settings::addControlFile('consolecolors.txt', loader => [\&parseSectionedFile, \%consoleColors]);
	Settings::addControlFile('routeweights.txt',  loader => [\&parseDataFile, \%routeWeights]);
	Settings::addControlFile('arrowcraft.txt',  loader => [\&parseDataFile_lc, \%arrowcraft_items]);

	Settings::addTableFile(Settings::getRecvPacketsFilename(),
		loader => [\&parseDataFile2, \%rpackets],
		autoSearch => 0);
	Settings::addTableFile('cities.txt',      loader => [\&parseROLUT, \%cities_lut]);
	Settings::addTableFile('commanddescriptions.txt', loader => [\&parseCommandsDescription, \%descriptions]);
	Settings::addTableFile('directions.txt',  loader => [\&parseDataFile2, \%directions_lut]);
	Settings::addTableFile('elements.txt',    loader => [\&parseROLUT, \%elements_lut]);
	Settings::addTableFile('emotions.txt',    loader => [\&parseEmotionsFile, \%emotions_lut]);
	Settings::addTableFile('equiptypes.txt',  loader => [\&parseDataFile2, \%equipTypes_lut]);
	Settings::addTableFile('haircolors.txt',  loader => [\&parseDataFile2, \%haircolors]);
	Settings::addTableFile('headgears.txt',   loader => [\&parseArrayFile, \@headgears_lut]);
	Settings::addTableFile('items.txt',       loader => [\&parseROLUT, \%items_lut]);
	Settings::addTableFile('itemsdescriptions.txt',   loader => [\&parseRODescLUT, \%itemsDesc_lut]);
	Settings::addTableFile('itemslots.txt',   loader => [\&parseROSlotsLUT, \%itemSlots_lut]);
	Settings::addTableFile('itemslotcounttable.txt',  loader => [\&parseROLUT, \%itemSlotCount_lut]);
	Settings::addTableFile('itemtypes.txt',   loader => [\&parseDataFile2, \%itemTypes_lut]);
	Settings::addTableFile('maps.txt',        loader => [\&parseROLUT, \%maps_lut]);
	Settings::addTableFile('monsters.txt',    loader => [\&parseDataFile2, \%monsters_lut]);
	Settings::addTableFile('npcs.txt',        loader => [\&parseNPCs, \%npcs_lut]);
	Settings::addTableFile('packetdescriptions.txt',  loader => [\&parseSectionedFile, \%packetDescriptions]);
	Settings::addTableFile('portals.txt',     loader => [\&parsePortals, \%portals_lut]);
	Settings::addTableFile('portalsLOS.txt',  loader => [\&parsePortalsLOS, \%portals_los]);
	Settings::addTableFile('servers.txt',     loader => [\&parseSectionedFile, \%masterServers]);
	Settings::addTableFile('sex.txt',         loader => [\&parseDataFile2, \%sex_lut]);
	Settings::addTableFile('skills.txt',      loader => \&Skill::StaticInfo::parseSkillsDatabase);
	Settings::addTableFile('spells.txt',      loader => [\&parseDataFile2, \%spells_lut]);
	Settings::addTableFile('skillsdescriptions.txt',  loader => [\&parseRODescLUT, \%skillsDesc_lut]);
	Settings::addTableFile('skillssp.txt',    loader => [\&parseSkillsSPLUT, \%skillsSP_lut]);
	Settings::addTableFile('skillssp.txt',    loader => \&Skill::StaticInfo::parseSPDatabase);
	Settings::addTableFile('skillsstatus.txt',        loader => [\&parseDataFile2, \%skillsStatus]);
	Settings::addTableFile('skillsailments.txt',      loader => [\&parseDataFile2, \%skillsAilments]);
	Settings::addTableFile('skillsstate.txt', loader => [\&parseDataFile2, \%skillsState]);
	Settings::addTableFile('skillslooks.txt', loader => [\&parseDataFile2, \%skillsLooks]);
	Settings::addTableFile('skillsarea.txt',  loader => [\&parseDataFile2, \%skillsArea]);
	Settings::addTableFile('skillsencore.txt',        loader => [\&parseList, \%skillsEncore]);

	use encoding 'utf8';

	Plugins::callHook('start2');
	eval {
		my $progressHandler = sub {
			my ($filename) = @_;
			message TF("Loading %s...\n", $filename);
		};
		Settings::loadAll($progressHandler);
	};
	if (my $e = caught('UTF8MalformedException')) {
		$interface->errorDialog(TF(
			"The file %s must be valid UTF-8 encoded, which it is \n" .
			"currently not. To solve this prolem, please use Notepad\n" .
			"to save that file as valid UTF-8.",
			$e->textfile));
		exit 1;
	} elsif (my $e = caught('FileNotFoundException')) {
		$interface->errorDialog(TF("Unable to load the file %s.", $e->filename));
		exit 1;
	} elsif ($@) {
		die $@;
	}
	Plugins::callHook('start3');

	if ($config{'adminPassword'} eq 'x' x 10) {
		Log::message(T("\nAuto-generating Admin Password due to default...\n"));
		configModify("adminPassword", vocalString(8));
	#} elsif ($config{'adminPassword'} eq '') {
	#	# This is where we protect the stupid from having a blank admin password
	#	Log::message(T("\nAuto-generating Admin Password due to blank...\n"));
	#	configModify("adminPassword", vocalString(8));
	} elsif ($config{'secureAdminPassword'} eq '1') {
		# This is where we induldge the paranoid and let them have session generated admin passwords
		Log::message(T("\nGenerating session Admin Password...\n"));
		configModify("adminPassword", vocalString(8));
	}

	Log::message("\n");
}

sub initNetworking {
	our $XKore_dontRedirect = 0;
	my $XKore_version = $config{XKore} ? $config{XKore} : $sys{XKore};
	eval {
		if ($XKore_version eq "1" || $XKore_version eq "inject") {
			# Inject DLL to running Ragnarok process
			require Network::XKore;
			$net = new Network::XKore;
		} elsif ($XKore_version eq "2") {
			# Run as a proxy bot, allowing Ragnarok to connect while botting
			require Network::DirectConnection;
			require Network::XKore2;
			$net = new Network::DirectConnection;
			Network::XKore2::start();
		} elsif ($XKore_version eq "3" || $XKore_version eq "proxy") {
			# Proxy Ragnarok client connection
			require Network::XKoreProxy;
			$net = new Network::XKoreProxy;
		} else {
			# Run as a standalone bot, with no interface to the official RO client
			require Network::DirectConnection;
			$net = new Network::DirectConnection;
		}
	};
	if ($@) {
		# Problem with networking.
		$interface->errorDialog($@);
		exit 1;
	}

	if ($sys{bus}) {
		require Bus::Client;
		require Bus::Handlers;
		my $host = $sys{bus_server_host};
		my $port = $sys{bus_server_port};
		$host = undef if ($host eq '');
		$port = undef if ($port eq '');
		$bus = new Bus::Client(host => $host, port => $port);
		our $busMessageHandler = new Bus::Handlers($bus);
	}
	
	Network::PaddedPackets::init();
}

sub initPortalsDatabase {
	Log::message(T("Checking for new portals... "));
	if (compilePortals_check()) {
		Log::message(T("found new portals!\n"));
		my $choice = $interface->showMenu(
			T("New portals have been added to the portals database. " .
			"The portals database must be compiled before the new portals can be used. " .
			"Would you like to compile portals now?\n"),
			[T("Yes, compile now."), T("No, don't compile it.")],
			title => T("Compile portals?"));
		if ($choice == 0) {
			Log::message(T("compiling portals") . "\n\n");
			compilePortals();
		} else {
			Log::message(T("skipping compile") . "\n\n");
		}
	} else {
		Log::message(T("none found\n\n"));
	}
}

sub promptFirstTimeInformation {
	if ($net->version != 1) {
		my $msg;
		if (!$config{username}) {
			$msg = $interface->query(T("Please enter your Ragnarok Online username."));
			if (!defined($msg)) {
				exit;
			}
			configModify('username', $msg, 1);
		}
		if (!$config{password}) {
			$msg = $interface->query(T("Please enter your Ragnarok Online password."), isPassword => 1);
			if (!defined($msg)) {
				exit;
			}
			configModify('password', $msg, 1);
		}
	}

	if ($config{master} eq "" || $config{master} =~ /^\d+$/ || !exists $masterServers{$config{master}}) {
		my @servers = sort { lc($a) cmp lc($b) } keys(%masterServers);
		my $choice = $interface->showMenu(
			T("Please choose a master server to connect to."),
			\@servers,
			title => T("Master servers"));
		if ($choice == -1) {
			exit;
		} else {
			configModify('master', $servers[$choice], 1);
		}
	}
}

sub finalInitialization {
	$incomingMessages = new Network::MessageTokenizer(\%rpackets);
	$outgoingClientMessages = new Network::MessageTokenizer(\%rpackets);

	$KoreStartTime = time;
	$conState = 1;
	our $nextConfChangeTime;
	$bExpSwitch = 2;
	$jExpSwitch = 2;
	$totalBaseExp = 0;
	$totalJobExp = 0;
	$startTime_EXP = time;
	$taskManager = new TaskManager();

	$itemsList = new ActorList('Actor::Item');
	$monstersList = new ActorList('Actor::Monster');
	$playersList = new ActorList('Actor::Player');
	$petsList = new ActorList('Actor::Pet');
	$npcsList = new ActorList('Actor::NPC');
	$portalsList = new ActorList('Actor::Portal');
	$slavesList = new ActorList('Actor::Slave');
	foreach my $list ($itemsList, $monstersList, $playersList, $petsList, $npcsList, $portalsList, $slavesList) {
		$list->onAdd()->add(undef, \&actorAdded);
		$list->onRemove()->add(undef, \&actorRemoved);
		$list->onClearBegin()->add(undef, \&actorListClearing);
	}

	StdHttpReader::init();
	initStatVars();
	initRandomRestart();
	initUserSeed();
	initConfChange();
	Log::initLogFiles();
	$timeout{'injectSync'}{'time'} = time;

	Log::message("\n");

	Plugins::callHook('initialized');
	XSTools::initVersion();
}


#######################################
# VARIABLE INITIALIZATION FUNCTIONS
#######################################

# Calculate next random restart time.
# The restart time will be autoRestartMin + rand(autoRestartSeed)
sub initRandomRestart {
	if ($config{'autoRestart'}) {
		my $autoRestart = $config{'autoRestartMin'} + int(rand $config{'autoRestartSeed'});
		message TF("Next restart in %s\n", timeConvert($autoRestart)), "system";
		configModify("autoRestart", $autoRestart, 1);
	}
}

# Initialize random configuration switching time
sub initConfChange {
	my $i = 0;
	while (exists $ai_v{"autoConfChange_${i}_timeout"}) {
		delete $ai_v{"autoConfChange_${i}_timeout"};
		$i++;
	}

	$i = 0;
	while (exists $config{"autoConfChange_$i"}) {
		$ai_v{"autoConfChange_${i}_timeout"} = $config{"autoConfChange_${i}_minTime"} +
			int(rand($config{"autoConfChange_${i}_varTime"}));
		$i++;
	}
	$lastConfChangeTime = time;
}

# Initialize variables when you start a connection to a map server
sub initConnectVars {
	# we must use $chars[$config{char}] here because $char may not be set
	initMapChangeVars();
	if ($char) {
		$char->{skills} = {};
		delete $char->{mute_period};
		delete $char->{muted};
	}
	undef @skillsID;
	$useArrowCraft = 1;
}

# Initialize variables when you change map (after a teleport or after you walked into a portal)
sub initMapChangeVars {
	# we must use $chars[$config{char}] here because $char may not be set
	@portalsID_old = @portalsID;
	%portals_old = %portals;
	foreach (@portalsID_old) {
		next if (!$_ || !$portals_old{$_});
		$portals_old{$_}{gone_time} = time if (!$portals_old{$_}{gone_time});
	}

	# this is just used for portalRecord (add opposite portal by guessing method)
	if ($char) {
		$char->{old_pos_to} = {%{$char->{pos_to}}} if ($char->{pos_to});
		delete $char->{sitting};
		delete $char->{dead};
		delete $char->{warp};
		delete $char->{casting};
		delete $char->{homunculus}{appear_time};
		$char->inventory->clear();
	}
	$timeout{play}{time} = time;
	$timeout{ai_sync}{time} = time;
	$timeout{ai_sit_idle}{time} = time;
	$timeout{ai_teleport}{time} = time;
	$timeout{ai_teleport_idle}{time} = time;
	$timeout{ai_teleport_safe_force}{time} = time;

	delete $timeout{ai_teleport_retry}{time};
	delete $timeout{ai_teleport_delay}{time};

	undef %incomingDeal;
	undef %outgoingDeal;
	undef %currentDeal;
	undef $currentChatRoom;
	undef @currentChatRoomUsers;
	undef @itemsID;
	undef @identifyID;
	undef %repairList;
	undef @spellsID;
	undef @arrowCraftID;
	undef %items;
	undef %spells;
	undef %incomingParty;
	undef %talk;
	$ai_v{cart_time} = time + 60;
	$ai_v{inventory_time} = time + 60;
	$ai_v{temp} = {};
	$cart{inventory} = [];
	undef @venderItemList;
	undef $venderID;
	undef @venderListsID;
	undef %venderLists;
	undef %incomingGuild;
	undef @chatRoomsID;
	undef %chatRooms;
	undef %createdChatRoom;
	undef @lastpm;
	undef %incomingFriend;

	$itemsList->clear();
	$monstersList->clear();
	$playersList->clear();
	$petsList->clear();
	$portalsList->clear();
	$npcsList->clear();
	$slavesList->clear();

	@unknownPlayers = ();
	@unknownNPCs = ();
	@sellList = ();

	$shopstarted = 0;
	$timeout{ai_shop}{time} = time;
	$timeout{ai_storageAuto}{time} = time + 5;
	$timeout{ai_buyAuto}{time} = time + 5;
	$timeout{ai_shop}{time} = time;

	AI::clear("attack", "move");
	AI::SlaveManager::clear("attack", "route", "move");
	ChatQueue::clear;

	Plugins::callHook('packet_mapChange');

	$logAppend = ($config{logAppendUsername}) ? "_$config{username}_$config{char}" : '';
	if ($config{logAppendUsername} && index($Settings::storage_log_file, $logAppend) == -1) {
		$Settings::chat_log_file     = substr($Settings::chat_log_file,    0, length($Settings::chat_log_file)    - 4) . "$logAppend.txt";
		$Settings::storage_log_file  = substr($Settings::storage_log_file, 0, length($Settings::storage_log_file) - 4) . "$logAppend.txt";
		$Settings::shop_log_file     = substr($Settings::shop_log_file,    0, length($Settings::shop_log_file)    - 4) . "$logAppend.txt";
		$Settings::monster_log_file  = substr($Settings::monster_log_file, 0, length($Settings::monster_log_log)  - 4) . "$logAppend.txt";
		$Settings::item_log_file     = substr($Settings::item_log_file,    0, length($Settings::item_log_file)    - 4) . "$logAppend.txt";
	}
}

# Initialize variables when your character logs in
sub initStatVars {
	$totaldmg = 0;
	$dmgpsec = 0;
	$startedattack = 0;
	$monstarttime = 0;
	$monkilltime = 0;
	$elasped = 0;
	$totalelasped = 0;
	$statChanged = 0;
	$skillChanged = 0;
}


#####################################################
# MISC. MAIN LOOP FUNCTIONS
#####################################################


# This function is called every time in the main loop, when OpenKore has been
# fully initialized.
sub mainLoop_initialized {
	Benchmark::begin("mainLoop_part1") if DEBUG;

	# Handle connection states
	$net->checkConnection();

	# Receive and handle data from the RO server
	my $data = $net->serverRecv;
	if (defined($data) && length($data) > 0) {
		Benchmark::begin("parseMsg") if DEBUG;

		my $type;
		$incomingMessages->add($data);
		while ($data = $incomingMessages->readNext(\$type)) {
			if ($type == Network::MessageTokenizer::KNOWN_MESSAGE) {
				parseIncomingMessage($data);
			} else {
				if ($type == Network::MessageTokenizer::UNKNOWN_MESSAGE) {
					# Unknown message - ignore it
					my $messageID = Network::MessageTokenizer::getMessageID($data);
					if (!existsInList($config{debugPacket_exclude}, $messageID)) {
						warning TF("Unknown packet - %s\n", $messageID), "connection";
						visualDump($data, "<< Received unknown packet") if ($config{debugPacket_unparsed});
					}
				} elsif ($config{debugPacket_received}) {
					debug "Received account ID\n", "parseMsg", 0 ;
				}
				# Pass it along to the client, whatever it is
				$net->clientSend($data);
			}
		}
		$net->clientFlush() if (UNIVERSAL::isa($net, 'Network::XKoreProxy'));
		Benchmark::end("parseMsg") if DEBUG;
	}

	# Receive and handle data from the RO client
	$data = $net->clientRecv;
	if (defined($data) && length($data) > 0) {
		my $type;
		$outgoingClientMessages->add($data);
		while ($data = $outgoingClientMessages->readNext(\$type)) {
			parseOutgoingClientMessage($data);
		}
	}

	# GameGuard support
	if ($config{gameGuard} && ($net->version != 1 || ($net->version == 1 && $config{gameGuard} eq '2'))) {
		my $result = Poseidon::Client::getInstance()->getResult();
		if (defined($result)) {
			debug "Received Poseidon result.\n", "poseidon";
			$messageSender->encryptMessageID(\$result);
			$net->serverSend($result);
		}
	}

	Benchmark::end("mainLoop_part1") if DEBUG;
	Benchmark::begin("mainLoop_part2") if DEBUG;

	# Process AI
	if ($net->getState() == Network::IN_GAME && timeOut($timeout{ai}) && $net->serverAlive()) {
		Misc::checkValidity("AI (pre)");
		Benchmark::begin("ai") if DEBUG;
		AI::CoreLogic::iterate();
		Benchmark::end("ai") if DEBUG;
		Benchmark::begin("ai_homunculus") if DEBUG;
		AI::SlaveManager::iterate();
		Benchmark::end("ai_homunculus") if DEBUG;
		Misc::checkValidity("AI");
		return if $quit;
	}
	Misc::checkValidity("mainLoop_part2.1");
	$taskManager->iterate();

	Benchmark::end("mainLoop_part2") if DEBUG;
	Benchmark::begin("mainLoop_part3") if DEBUG;

	# Process bus events.
	$bus->iterate() if ($bus);
	Misc::checkValidity("mainLoop_part2.2");


	###### Other stuff that's run in the main loop #####

	if ($config{'autoRestart'} && time - $KoreStartTime > $config{'autoRestart'}
	 && $net->getState() == Network::IN_GAME && !AI::inQueue(qw/attack take items_take/)) {
		message T("\nAuto-restarting!!\n"), "system";

		if ($config{'autoRestartSleep'}) {
			my $sleeptime = $config{'autoSleepMin'} + int(rand $config{'autoSleepSeed'});
			$timeout_ex{'master'}{'timeout'} = $sleeptime;
			$sleeptime = $timeout{'reconnect'}{'timeout'} if ($sleeptime < $timeout{'reconnect'}{'timeout'});
			message TF("Sleeping for %s\n", timeConvert($sleeptime)), "system";
		} else {
			$timeout_ex{'master'}{'timeout'} = $timeout{'reconnect'}{'timeout'};
		}

		$timeout_ex{'master'}{'time'} = time;
		$KoreStartTime = time + $timeout_ex{'master'}{'timeout'};
		AI::clear();
		AI::SlaveManager::clear();
		undef %ai_v;
		$net->serverDisconnect;
		$net->setState(Network::NOT_CONNECTED);
		undef $conState_tries;
		initRandomRestart();
	}
	
	Misc::checkValidity("mainLoop_part2.3");

	# Automatically switch to a different config file
	# based on certain conditions
	if ($net->getState() == Network::IN_GAME && timeOut($AI::Timeouts::autoConfChangeTime, 0.5)
	 && !AI::inQueue(qw/attack take items_take/)) {
		my $selected;
		my $i = 0;
		while (exists $config{"autoConfChange_$i"}) {
			if ($config{"autoConfChange_$i"}
			 && ( !$config{"autoConfChange_${i}_minTime"} || timeOut($lastConfChangeTime, $ai_v{"autoConfChange_${i}_timeout"}) )
			 && inRange($char->{lv}, $config{"autoConfChange_${i}_lvl"})
			 && inRange($char->{lv_job}, $config{"autoConfChange_${i}_joblvl"})
			 && ( !$config{"autoConfChange_${i}_isJob"} || $jobs_lut{$char->{jobID}} eq $config{"autoConfChange_${i}_isJob"} )
			) {
				$selected = $config{"autoConfChange_$i"};
				last;
			}
			$i++;
		}

		if ($selected) {
			# Choose a random configuration file
			my @files = split(/,+/, $selected);
			my $file = $files[rand(@files)];
			message TF("Changing configuration file (from \"%s\" to \"%s\")...\n", $Settings::config_file, $file), "system";

			# A relogin is necessary if the server host/port, username
			# or char is different.
			my $oldMaster = $masterServer;
			my $oldUsername = $config{'username'};
			my $oldChar = $config{'char'};

			switchConfigFile($file);

			my $master = $masterServer = $masterServers{$config{'master'}};
			if ($net->version != 1
			 && $oldMaster->{ip} ne $master->{ip}
			 || $oldMaster->{port} ne $master->{port}
			 || $oldMaster->{master_version} ne $master->{master_version}
			 || $oldMaster->{version} ne $master->{version}
			 || $oldUsername ne $config{'username'}
			 || $oldChar ne $config{'char'}) {
				AI::clear;
				AI::SlaveManager::clear();
				relog();
			} else {
				AI::clear("move", "route", "mapRoute");
				AI::SlaveManager::clear("move", "route", "mapRoute");
			}

			initConfChange();
		}

		$AI::Timeouts::autoConfChangeTime = time;
	}

	processStatisticsReporting() unless ($sys{sendAnonymousStatisticReport} eq "0");

	# Update state.yml
	if (timeOut($AI::Timeouts::stateUpdate, 0.5)) {
		my %state;
		my $f;
		$AI::Timeouts::stateUpdate = time;

		if ($field{name} && $net->getState() == Network::IN_GAME) {
			my $pos = calcPosition($char);
			%state = (
				connectionState => 'in game',
				fieldName => $field{name},
				fieldBaseName => $field{baseName},
				charName => $char->{name},
				x => $pos->{x},
				y => $pos->{y}
			);
			$state{actors} = {};
			foreach my $actor (@{$npcsList->getItems()}, @{$playersList->getItems()}, @{$monstersList->getItems()}, @{$slavesList->getItems()}) {
				my $actorType = $actor->{actorType};
				$state{actors}{$actorType} ||= [];
				push @{$state{actors}{$actorType}}, {
					x => $actor->{pos_to}{x},
					y => $actor->{pos_to}{y}
				};
			}
		} else {
			%state = (
				connectionState => 'not logged in'
			);
		}
		if ($bus && $bus->getState() == Bus::Client::CONNECTED()) {
			$state{bus}{host} = $bus->serverHost();
			$state{bus}{port} = $bus->serverPort();
			$state{bus}{clientID} = $bus->ID();
		}

		if (open($f, ">:utf8", "$Settings::logs_folder/state_".$config{'username'}.".yml")) {
			my $writer = new Data::YAML::Writer();
			$writer->write(\%state, $f);
			close $f;
		}
	}

	Misc::checkValidity("mainLoop_part2.4");
	
	# Set interface title
	my $charName;
	my $title;
	$charName = "$char->{name}: " if ($char);
	if ($net->getState() == Network::IN_GAME) {
		my ($basePercent, $jobPercent, $weight, $pos);

		assert(defined $char);
		$basePercent = sprintf("%.2f", $char->{exp} / $char->{exp_max} * 100) if ($char->{exp_max});
		$jobPercent = sprintf("%.2f", $char->{exp_job} / $char->{exp_job_max} * 100) if ($char->{exp_job_max});
		$weight = int($char->{weight} / $char->{weight_max} * 100) . "%" if ($char->{weight_max});
		$pos = " : $char->{pos_to}{x},$char->{pos_to}{y} " . $field->name() if ($char->{pos_to} && $field);

		# Translation Comment: Interface Title with character status
		$title = TF("%s B%s (%s), J%s (%s) : w%s%s - %s",
			$charName, $char->{lv}, $basePercent . '%',
			$char->{lv_job}, $jobPercent . '%',
			$weight, $pos, $Settings::NAME);

	} elsif ($net->getState() == Network::NOT_CONNECTED) {
		# Translation Comment: Interface Title
		$title = TF("%sNot connected - %s", $charName, $Settings::NAME);
	} else {
		# Translation Comment: Interface Title
		$title = TF("%sConnecting - %s", $charName, $Settings::NAME);
	}
	my %args = (return => $title);
	Plugins::callHook('mainLoop::setTitle',\%args);
	$interface->title($args{return});

	Misc::checkValidity("mainLoop_part3");
	Benchmark::end("mainLoop_part3") if DEBUG;
}

# Anonymous statistics reporting. This gives us insight about
# servers that our users bot on.
sub processStatisticsReporting {
	our %statisticsReporting;
	if (!$statisticsReporting{reported} && $config{master} && $config{username}) {
		if (!$statisticsReporting{http}) {
			use Utils qw(urlencode);
			import Utils::Whirlpool qw(whirlpool_hex);

			# Note that ABSOLUTELY NO SENSITIVE INFORMATION about the
			# user is sent. The username is filtered through an
			# irreversible hashing algorithm before it is sent to the
			# server. It is impossible to deduce the user's username
			# from the data sent to the server.
			#
			# If you're still not convinced about the security of this,
			# please read the following web pages for more details and explanation:
			#   http://www.openkore.com/statistics.php
			# -and-
			#   http://forums.openkore.com/viewtopic.php?t=28044
			my $url = "http://www.openkore.com/statistics.php";
			my $post = "server=" . urlencode($config{master});
			$post .= "&product=" . urlencode($Settings::NAME);
			$post .= "&version=" . urlencode($Settings::VERSION);
			$post .= "&uid=" . urlencode(whirlpool_hex($config{master} . $config{username} . $userSeed));
			$statisticsReporting{http} = new StdHttpReader($url, $post);
			debug "Posting anonymous usage statistics to $url\n", "statisticsReporting";
		}

		my $http = $statisticsReporting{http};
		if ($http->getStatus() == HttpReader::DONE) {
			$statisticsReporting{reported} = 1;
			delete $statisticsReporting{http};
			debug "Statistics posting completed.\n", "statisticsReporting";

		} elsif ($http->getStatus() == HttpReader::ERROR) {
			$statisticsReporting{reported} = 1;
			delete $statisticsReporting{http};
			debug "Statistics posting failed: " . $http->getError() . "\n", "statisticsReporting";
		}

	} elsif (!$statisticsReporting{infoPosted} && $masterServer && $masterServer->{ip}
	      && $config{master} && $net && $net->getState() == Network::IN_GAME && $monstarttime) {
		if (!$statisticsReporting{http}) {
			my $url = "http://www.openkore.com/server-info.php";
			my $serverData = "";
			foreach my $key (sort keys %{$masterServer}) {
				$serverData .= "$key $masterServer->{$key}\n";
			}
			my $post = "server=" . urlencode($config{master}) . "&data=" . urlencode($serverData);
			$statisticsReporting{http} = new StdHttpReader($url, $post);
			debug "Posting server info to $url\n", "statisticsReporting";
		}

		my $http = $statisticsReporting{http};
		if ($http->getStatus() == HttpReader::DONE) {
			$statisticsReporting{infoPosted} = 1;
			delete $statisticsReporting{http};
			debug "Server info posting completed.\n", "statisticsReporting";

		} elsif ($http->getStatus() == HttpReader::ERROR) {
			$statisticsReporting{infoPosted} = 1;
			delete $statisticsReporting{http};
			debug "Server info posting failed: " . $http->getError() . "\n", "statisticsReporting";
		}
	}
}

sub parseInput {
	my $input = shift;
	my $printType;
	my ($hook, $msg);
	$printType = shift if ($net && $net->clientAlive);

	debug("Input: $input\n", "parseInput", 2);

	if ($printType) {
		my $hookOutput = sub {
			my ($type, $domain, $level, $globalVerbosity, $message, $user_data) = @_;
			$msg .= $message if ($type ne 'debug' && $level <= $globalVerbosity);
		};
		$hook = Log::addHook($hookOutput);
		$interface->writeOutput("console", "$input\n");
	}
	$XKore_dontRedirect = 1;

	Commands::run($input);

	if ($printType) {
		Log::delHook($hook);
		if (defined $msg && $net->getState() == Network::IN_GAME && $config{XKore_silent}) {
			$msg =~ s/\n*$//s;
			$msg =~ s/\n/\\n/g;
			sendMessage($messageSender, "k", $msg);
		}
	}
	$XKore_dontRedirect = 0;
}


#######################################
#######################################
# Parse RO Client Send Message
#######################################
#######################################

sub parseOutgoingClientMessage {
	use bytes;
	no encoding 'utf8';
	my ($msg) = @_;

	my $sendMsg = $msg;
	if (length($msg) >= 4 && $net->getState() >= 4 && length($msg) >= unpack("v1", substr($msg, 0, 2))) {
		Network::Receive->decrypt(\$msg, $msg);
	}
	my $switch = Network::MessageTokenizer::getMessageID($msg);
	if ($config{'debugPacket_ro_sent'} && !existsInList($config{'debugPacket_exclude'}, $switch)
	   || $config{debugPacket_include_dumpMethod} && existsInList($config{'debugPacket_include'}, $switch)) {
		my $label = $packetDescriptions{Send}{$switch} ?
			" - $packetDescriptions{Send}{$switch}" : '';
		
		if ($config{debugPacket_ro_sent} == 1) {
			debug "Packet SENT_BY_CLIENT: $switch$label\n", "parseSendMsg", 0;
		} elsif ($config{debugPacket_ro_sent} == 2) {
			visualDump($sendMsg, $switch . $label);
		}
		if ($config{debugPacket_include_dumpMethod} == 1) {
			debug "Packet: $switch$label\n", "parseMsg", 0;
		} elsif ($config{debugPacket_include_dumpMethod} == 2) {
			visualDump($sendMsg, $switch . $label);
		} elsif ($config{debugPacket_include_dumpMethod} == 3) {
			dumpData($msg,1);
		} elsif ($config{debugPacket_include_dumpMethod} == 4) {
			open DUMP, ">> DUMP_lines.txt";
			print DUMP sprintf(unpack('H*', $msg) . "\n");
			close DUMP;
		}
	}

	Plugins::callHook('RO_sendMsg_pre', {switch => $switch, msg => $msg, realMsg => \$sendMsg});
	
	my $serverType = $masterServer->{serverType};

	# If the player tries to manually do something in the RO client, disable AI for a small period
	# of time using ai_clientSuspend().

	if ($masterServer->{syncID} && $switch eq sprintf('%04X', hex($masterServer->{syncID}))) {
		#syncSync support for XKore 1 mode
		$syncSync = substr($msg, $masterServer->{syncTickOffset}, 4);

	} elsif ($switch eq "0065") {
		# Login to character server
		$incomingMessages->nextMessageMightBeAccountID();

	} elsif ($switch eq "0066") {
		# Login character selected
		configModify("char", unpack("C*",substr($msg, 2, 1)));

	} elsif (
		($switch eq "0072" && ($serverType == 0 || $serverType == 21 || $serverType == 22)) ||
		($switch eq "00F3" && $serverType == 18)
	) {
		# Map login
		$incomingMessages->nextMessageMightBeAccountID();
		if ($serverType == 0 && $config{sex} ne "") {
			$sendMsg = substr($sendMsg, 0, 18) . pack("C",$config{'sex'});
		}

	} elsif ($switch eq "00A7") {
		if($masterServer && $masterServer->{paddedPackets}) {
			$syncSync = substr($msg, 8, 4);
		}

	} elsif ($switch eq "007E") {
		if ($masterServer && $masterServer->{paddedPackets}) {
			$syncSync = substr($msg, 4, 4);
		}

	} elsif ($switch eq "007D") {
		# Map loaded
		$packetParser->changeToInGameState();
		AI::clear("clientSuspend");
		$timeout{ai}{time} = time;
		if ($firstLoginMap) {
			undef $sentWelcomeMessage;
			undef $firstLoginMap;
		}
		$timeout{'welcomeText'}{'time'} = time;
		$ai_v{portalTrace_mapChanged} = time;
		# syncSync support for XKore 1 mode
		if($masterServer->{serverType} == 11) {
			$syncSync = substr($msg, 8, 4);
		} else {
			# formula: MapLoaded_len + Sync_len - 4 - Sync_packet_last_junk
			$syncSync = substr($msg, $masterServer->{mapLoadedTickOffset}, 4);
		}
		message T("Map loaded\n"), "connection";
		
		Plugins::callHook('map_loaded');

	} elsif ($switch eq "0085") {
		#if ($masterServer->{serverType} == 0 || $masterServer->{serverType} == 1 || $masterServer->{serverType} == 2) {
		#	#Move
		#	AI::clear("clientSuspend");
		#	makeCoords(\%coords, substr($msg, 2, 3));
		#	ai_clientSuspend($switch, (distance($char->{'pos'}, \%coords) * $char->{walk_speed}) + 4);
		#}

	} elsif ($switch eq "0089") {
		if ($masterServer->{serverType} == 0) {
			# Attack
			if (!$config{'tankMode'} && !AI::inQueue("attack")) {
				AI::clear("clientSuspend");
				ai_clientSuspend($switch, 2, unpack("C*",substr($msg,6,1)), substr($msg,2,4));
			} else {
				undef $sendMsg;
			}
		}
		#undef $sendMsg;

	} elsif (($switch eq "008C" && ($masterServer->{serverType} == 0 || $masterServer->{serverType} == 1 || $masterServer->{serverType} == 2 || $masterServer->{serverType} == 6 || $masterServer->{serverType} == 7 || $masterServer->{serverType} == 10 || $masterServer->{serverType} == 11 || $masterServer->{serverType} == 21 || $masterServer->{serverType} == 22)) ||
		($switch eq "00F3" && ($masterServer->{serverType} == 3 || $masterServer->{serverType} == 5 || $masterServer->{serverType} == 8 || $masterServer->{serverType} == 9 || $masterServer->{serverType} == 15)) ||
		($switch eq "009F" && $masterServer->{serverType} == 4) ||
		($switch eq "007E" && $masterServer->{serverType} == 12) ||
		($switch eq "0190" && ($masterServer->{serverType} == 13 || $masterServer->{serverType} == 18)) ||
		($switch eq "0085" && $masterServer->{serverType} == 14) ||	# Public chat

		$switch eq "0108" ||	# Party chat

		$switch eq "017E") {	# Guild chat

		my $length = unpack("v",substr($msg,2,2));
		my $message = substr($msg, 4, $length - 4);
		my ($chat) = $message =~ /^[\s\S]*? : ([\s\S]*)\000?/;
		$chat =~ s/^\s*//;

		stripLanguageCode(\$chat);

		my $prefix = quotemeta $config{'commandPrefix'};
		if ($chat =~ /^$prefix/) {
			$chat =~ s/^$prefix//;
			$chat =~ s/^\s*//;
			$chat =~ s/\s*$//;
			$chat =~ s/\000*$//;
			parseInput($chat, 1);
			undef $sendMsg;
		}

	} elsif ($switch eq "0096") {
		# Private message
		my $length = unpack("v",substr($msg,2,2));
		my ($user) = substr($msg, 4, 24) =~ /([\s\S]*?)\000/;
		my $chat = substr($msg, 28, $length - 29);
		$chat =~ s/^\s*//;

		# Ensures: $user and $chat are String
		$user = I18N::bytesToString($user);
		$chat = I18N::bytesToString($chat);
		stripLanguageCode(\$chat);

		my $prefix = quotemeta $config{commandPrefix};
		if ($chat =~ /^$prefix/) {
			$chat =~ s/^$prefix//;
			$chat =~ s/^\s*//;
			$chat =~ s/\s*$//;
			parseInput($chat, 1);
			undef $sendMsg;
		} else {
			undef %lastpm;
			$lastpm{msg} = $chat;
			$lastpm{user} = $user;
			push @lastpm, {%lastpm};
		}

	} elsif (($switch eq "009B" && $masterServer->{serverType} == 0) ||
		($switch eq "009B" && $masterServer->{serverType} == 1) ||
		($switch eq "009B" && $masterServer->{serverType} == 2) ||
		($switch eq "0085" && $masterServer->{serverType} == 3) ||
		($switch eq "00F3" && $masterServer->{serverType} == 4) ||
		($switch eq "0085" && $masterServer->{serverType} == 5) ||
		#($switch eq "009B" && $masterServer->{serverType} == 6) || serverType 6 uses what?
		($switch eq "009B" && $masterServer->{serverType} == 7) ||
		($switch eq "0072" && $masterServer->{serverType} == 13)) { # rRO
		# Look
		
		if ($char) {
			if ($masterServer->{serverType} == 0) {
				$char->{look}{head} = unpack("C", substr($msg, 2, 1));
				$char->{look}{body} = unpack("C", substr($msg, 4, 1));
			} elsif ($masterServer->{serverType} == 1 ||
				$masterServer->{serverType} == 2 ||
				$masterServer->{serverType} == 4 ||
				$masterServer->{serverType} == 7) {
				$char->{look}{head} = unpack("C", substr($msg, 6, 1));
				$char->{look}{body} = unpack("C", substr($msg, 14, 1));
			} elsif ($masterServer->{serverType} == 3) {
				$char->{look}{head} = unpack("C", substr($msg, 12, 1));
				$char->{look}{body} = unpack("C", substr($msg, 22, 1));
			} elsif ($masterServer->{serverType} == 5) {
				$char->{look}{head} = unpack("C", substr($msg, 8, 1));
				$char->{look}{body} = unpack("C", substr($msg, 16, 1));
			} elsif ($masterServer->{serverType} == 13) { # rRO
				$char->{look}{head} = unpack("C", substr($msg, 2, 1));
				$char->{look}{body} = unpack("C", substr($msg, 4, 1));
			}
		}

	} elsif ($switch eq "009F") {
		if ($masterServer->{serverType} == 0) {
			# Take
			AI::clear("clientSuspend");
			ai_clientSuspend($switch, 2, substr($msg,2,4));
		}

	} elsif ($switch eq "00B2") {
		# Trying to exit (respawn)
		AI::clear("clientSuspend");
		ai_clientSuspend($switch, 10);

	} elsif ($switch eq "018A") {
		# Trying to exit
		AI::clear("clientSuspend");
		ai_clientSuspend($switch, 10);

	} elsif ($switch eq "0149") {
		# Chat/skill mute
		undef $sendMsg;

	} elsif ($switch eq "01B2") {
		# client started a shop manually
		$shopstarted = 1;
		
	} elsif ($switch eq "012E") {
		# client stopped shop manually
		$shopstarted = 0;
	}

	if ($sendMsg ne "") {
		$messageSender->encryptMessageID(\$sendMsg);
		$net->serverSend($sendMsg);
	}

	# This should be changed to packets that haven't been parsed yet, in a similar manner
	# as parseMsg
	return "";
}


#######################################
#######################################
#Parse Message
#######################################
#######################################


##
# void parseIncomingMessage(Bytes msg)
# msg: The data to parse, as received from the socket.
#
# Parse network data sent by the RO server.
sub parseIncomingMessage {
	my ($msg) = @_;

	# Determine packet switch
	my $switch = Network::MessageTokenizer::getMessageID($msg);
	if (length($msg) >= 4 && substr($msg, 0, 4) ne $accountID && $net->getState() >= Network::CONNECTED_TO_CHAR_SERVER
	 && $lastswitch ne $switch && length($msg) >= unpack("v1", substr($msg, 0, 2))) {
		# The decrypt below casued annoying unparsed errors (at least in serverType  2)
		if ($masterServer->{serverType} != 2) {
			Network::Receive->decrypt(\$msg, $msg);
			$switch = Network::MessageTokenizer::getMessageID($msg);
		}
	}

	# The user is running in X-Kore mode and wants to switch character or gameGuard type 2 after 0259 tag 02.
	# We're now expecting an accountID, unless the server has replicated packet 0259 (server-side bug).
	if ($net->getState() == 2.5 && (!$config{gameGuard} || ($switch ne '0259' && $config{gameGuard} eq "2"))) {
		if (length($msg) >= 4) {
			$net->setState(Network::CONNECTED_TO_MASTER_SERVER);
			$accountID = substr($msg, 0, 4);
			debug "Selecting character, new accountID: ".unpack("V", $accountID)."\n", "connection";
			$net->clientSend($accountID);
			return substr($msg, 4);
		} else {
			return $msg;
		}
	}

	$lastswitch = $switch;
	if ($config{debugPacket_received} && !existsInList($config{'debugPacket_exclude'}, $switch)) {
		my $label = $packetDescriptions{Recv}{$switch} ?
			"[$packetDescriptions{Recv}{$switch}]" : '';
		if ($config{debugPacket_received} == 1) {
			debug sprintf("Received packet: %-4s    [%2d bytes]  %s\n", $switch, length($msg), $label),
				"parseMsg", 0;
		} else {
			visualDump($msg, "<< Received packet: $switch  $label");
		}
	}

	if ($config{debugPacket_include_dumpMethod} && existsInList($config{'debugPacket_include'}, $switch)) {
		my $label = $packetDescriptions{Recv}{$switch} ?
			" ($packetDescriptions{Recv}{$switch})" : '';
		if ($config{debugPacket_include_dumpMethod} == 1) {
			debug "Packet: $switch$label\n", "parseMsg", 0;
		} elsif ($config{debugPacket_include_dumpMethod} == 2) {
			visualDump($msg, "$switch$label");
		} elsif ($config{debugPacket_include_dumpMethod} == 3) {
			dumpData($msg,1);
		} elsif ($config{debugPacket_include_dumpMethod} == 4) {
			open DUMP, ">> DUMP_lines.txt";
			print DUMP sprintf(unpack('H*', $msg) . "\n");
			close DUMP;
		}
	}

	Plugins::callHook('parseMsg/pre', {switch => $switch, msg => $msg, msg_size => length($msg)});

	if (!$packetParser->willMangle($switch)) {
		# If we're running in X-Kore mode, pass the message back to the RO client.
		$net->clientSend($msg);
	}

	$lastPacketTime = time;
	if ($packetParser &&
		(my $args = $packetParser->parse($msg))) {
		# Use the new object-oriented packet parser
		if ($config{debugPacket_received} > 2 &&
		    !existsInList($config{'debugPacket_exclude'}, $switch)) {
			my $switch = $args->{switch};
			my $packet = $packetParser->{packet_list}{$switch};
			my ($name, $packString, $varNames) = @{$packet};

			my @vars = ();
			for my $varName (@{$varNames}) {
				message "$varName = $args->{$varName}\n";
			}
		}

		if ($packetParser->willMangle($switch)) {
			my $ret = $packetParser->mangle($args);
			if (!$ret) {
				# Packet was not mangled
				$net->clientSend($args->{RAW_MSG});
			} elsif ($ret == 1) {
				# Packet was mangled
				$net->clientSend($packetParser->reconstruct($args));
			} else {
				# Packet was suppressed
			}
		}
	}
}

return 1;
