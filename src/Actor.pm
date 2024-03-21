#########################################################################
#  OpenKore - Base class for all actor objects
#  Copyright (c) 2005 OpenKore Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 6776 $
#  $Id: Actor.pm 6776 2009-07-19 15:22:22Z eternalharvest $
#
#########################################################################
##
# MODULE DESCRIPTION: Base class for all actor objects
#
# The Actor class is a base class for all actor objects.
# An actor object is a monster or player (all members of %monsters and
# %players). Do not create an object of this class; use one of the
# subclasses instead.
#
# An actor object is also a hash.
#
# Child classes: @MODULE(Actor::Monster), @MODULE(Actor::Player), @MODULE(Actor::You),
# @MODULE(Actor::Item), @MODULE(Actor::Pet), @MODULE(Actor::Party), @MODULE(Actor::NPC),
# @MODULE(Actor::Portal)

package Actor;

use strict;
use Carp::Assert;
use Scalar::Util;
use Data::Dumper;
use Storable;
use Globals;
use Utils;
use Utils::CallbackList;
use Log qw(message error debug);
use Misc;

# Make it so that
#     print $actor;
# acts the same as
#     print $actor->nameString;
use overload '""' => \&_nameString;
# The eq operator checks whether two variables refer to compatible objects.
use overload 'eq' => \&_eq;
use overload 'ne' => \&_ne;
# The == operator is to check whether two variables refer to the
# exact same object.
use overload '==' => \&_isis;
use overload '!=' => \&_not_is;

sub _eq {
	return UNIVERSAL::isa($_[0], "Actor")
		&& UNIVERSAL::isa($_[1], "Actor")
		&& $_[0]->{ID} eq $_[1]->{ID};
}

sub _ne {
	return !&_eq;
}

# This function is needed to make the operator overload respect inheritance.
sub _nameString {
	my $self = shift;
	return $self->nameString(@_);
}

sub _isis {
	return Scalar::Util::refaddr($_[0]) == Scalar::Util::refaddr($_[1]);
}

sub _not_is {
	return !&_isis;
}

### CATEGORY: Class methods

# protected Actor->new(String actorType)
# actorType: A type name for this actor, like 'Player', 'Monster', etc.
# Requires: defined($actorType)
#
# A default abstract constructor that subclasses should call. Must not
# be directly used.
sub new {
	my ($class, $actorType) = @_;
	my %self = (
		actorType => $actorType,
		onNameChange => new CallbackList('onNameChange'),
		onUpdate => new CallbackList('onUpdate')
	);
	return bless \%self, $class;
}

##
# Actor Actor::get(Bytes ID)
# ID: an actor ID, in binary format.
# Returns: the associated Actor object, or a new Actor::Unknown object if not found.
# Requires: defined($ID)
# Ensures:  defined(result)
#
# Returns the Actor object for $ID. This function will look at the various
# actor lists. If $ID is not in any of the actor lists, it will return
# a new Actor::Unknown object.
sub get {
	my ($ID) = @_;
	assert(defined $ID) if DEBUG;

	if ($ID eq $accountID || $ID eq "\000\000\000\000") {
		# I put assertions here because $char seems to be unblessed sometimes.
		assert(defined $char, '$char must be defined') if DEBUG;
		assert(UNIVERSAL::isa($char, 'Actor::You'), '$char must be of class Actor::You') if DEBUG;
		return $char;
	} elsif ($items{$ID}) {
		return $items{$ID};
	} else {
		foreach my $list ($playersList, $monstersList, $npcsList, $petsList, $portalsList, $slavesList) {
			my $actor = $list->getByID($ID);
			if ($actor) {
				return $actor;
			}
		}
		return new Actor::Unknown($ID);
	}
}

### CATEGORY: Hash members

##
# String $Actor->{actorType}
# Invariant: defined(value)
#
# An identifier for this actor's type. The meaning for this field
# depends on the actor's class. For example, for Player actors,
# this is the job ID (though you should use $ActorPlayer->{jobID} instead).

##
# int $Actor->{binID}
# Invariant: value >= 0
#
# The index of this actor inside its associated actor list.

##
# Bytes $Actor->{ID}
# Invariant: length(value) == 4
#
# The server's internal unique ID for this actor (the actor's account ID).

##
# int $Actor->{nameID}
# Invariant: value >= 0
#
# $Actor->{ID} decoded into an 32-bit little endian integer.

##
# int $Actor->{appear_time}
# Invariant: value >= 0
#
# The time when this actor first appeared on screen.

##
# String $Actor->{actorType}
# Invariant: defined(value)
#
# A human-friendly name which describes this actor type.
# For instance, "Player", "Monster", "NPC", "You", etc.
# Do not confuse this with $Actor->{type}

##
# String $Actor->{name}
#
# The name of the actor, e.g. "Joe", "Jane", "Poring", etc.
# This field is undefined if the name for this actor isn't known yet,
# so generally you use use $Actor->name() instead, which automatically
# takes care of actor objects that don't have a name yet.

##
# Hash* $Actor->{pos}
#
# The position where this actor was, before its last movement.
# This is a reference to a hash, containing the items 'x' and 'y'.

##
# Hash* $Actor->{pos_to}
#
# The position where this actor is moving to, or (if the actor has finished moving),
# where it currently is. This is a reference to a hash, containing the items 'x' and 'y'.

##
# float $Actor->{walk_speed}
#
# The actor's walking speed, in blocks per second.

##
# float $Actor->{time_move}
#
# The time (as timestamp) at which the actor last moved.

##
# float $Actor->{time_move_calc}
#
# The time (in seconds) that the actor needs to move from $Actor->{pos} to $Actor->{pos_to}.


### CATEGORY: Methods

##
# String $Actor->nameString([Actor otherActor])
#
# Returns the name string of an actor, e.g. "Player pmak (3)",
# "Monster Poring (0)" or "You".
#
# If $otherActor is specified and is equal to $actor, then it will
# return 'self' or 'yourself' instead.
sub nameString {
	my ($self, $otherActor) = @_;

	return $self->selfString if $self->{ID} eq $otherActor->{ID};

	my $nameString = "$self->{actorType} " . $self->name;
	$nameString .= " ($self->{binID})" if defined $self->{binID};
	return $nameString;
}

##
# String $Actor->selfString()
#
# Returns 'itself' for monsters, or 'himself/herself' for players.
# ('yourself' is handled by Actor::You.nameString.)
sub selfString {
	return 'itself';
}

##
# String $Actor->name()
#
# Returns the name of an actor, e.g. "pmak" or "Unknown #300001".
sub name {
	my ($self) = @_;

	return $self->{name} || "Unknown #".unpack("V1", $self->{ID});
}

##
# void $Actor->setName(String name)
# name: A few name for this actor. Can be undef to indicate that this actor has lost its previous name.
#
# Assign a name to this actor. An 'onNameChange' and 'onUpdate' event will
# be triggered after the name is set.
sub setName {
	my ($self, $name) = @_;

	my $oldName = $self->{name};
	$self->{name} = $name;
	$self->{onNameChange}->call($self, { oldName => $oldName });
	$self->{onUpdate}->call($self);
}

##
# String $Actor->nameIdx()
#
# Returns the name and index of an actor, e.g. "pmak (0)" or "Unknown #300001 (1)".
sub nameIdx {
	my ($self) = @_;

	my $nameIdx = $self->name;
	$nameIdx .= " ($self->{binID})" if defined $self->{binID};
	return $nameIdx;

#	return $self->{name} || "Unknown #".unpack("V1", $self->{ID});
}

##
# String $Actor->verb(String you, String other)
#
# Returns $you if $actor is you; $other otherwise.
sub verb {
	my ($self, $you, $other) = @_;

	return $you if $self->isa('Actor::You');
	return $other;
}

##
# Hash $Actor->position()
#
# Returns the position of the actor.
sub position {
	my ($self) = @_;

	return calcPosition($self);
}

##
# float $Actor->distance([Actor otherActor])
#
# Returns the distance to another actor (defaults to yourself).
sub distance {
	my ($self, $otherActor) = @_;

	$otherActor ||= $char;
	return Utils::distance($self->position, $otherActor->position);
}

##
# float $Actor->blockDistance([Actor otherActor])
#
# Returns the block distance to another actor (defaults to yourself).
sub blockDistance {
	my ($self, $otherActor) = @_;

	$otherActor ||= $char;
	return Utils::blockDistance($self->position, $otherActor->position);
}

##
# boolean $Actor->snipable()
#
# Returns whether or not you have snipable LOS to the actor.
sub snipable {
	my ($self) = @_;

	return checkLineSnipable($char->position, $self->position);
}

##
# Actor $Actor->deepCopy()
# Ensures: defined(result)
#
# Create a deep copy of this actor object.
sub deepCopy {
	my ($self) = @_;

	# Some fields cannot be deep copied by dclone() because they contain
	# function references, so we'll do that manually.

	# Delete fields that cannot be copied by dclone() and store
	# them in a temporary place.
	my %deepCopyFields;
	my %hashCopies;
	foreach my $field ('onNameChange', 'onUpdate') {
		$deepCopyFields{$field} = $self->{$field};
		delete $self->{$field};
	}
	# $actor->{casting} may be a hash which contains a reference to another
	# Actor object.
	foreach my $field ('casting') {
		if ($self->{$field}) {
			$hashCopies{$field} = $self->{$field};
			delete $self->{$field};
		}
	}

	my $copy;
	eval {
		$copy = Storable::dclone($_[0]);
	};
	if ($@ =~ /Can't store CODE items/) {
		die "Actor hash $self contains CODE items:\n" .
			Dumper($self);
	} elsif ($@) {
		die $@;
	}

	# Restore the deleted fields in the original object,
	# and assign manually-created deep copies to the clone.
	foreach my $field (keys %deepCopyFields) {
		$self->{$field} = $deepCopyFields{$field};
		$copy->{$field} = $deepCopyFields{$field}->deepCopy;
	}
	foreach my $field (keys %hashCopies) {
		$self->{$field} = $hashCopies{$field};
		$copy->{$field} = {%{$hashCopies{$field}}};
	}

	return $copy;
}

##
# CallbackList $Actor->onNameChange()
# Ensures: defined(result)
#
# Returns the onNameChange event callback list.
# This event is triggered when the name of this actor has changed.
sub onNameChange {
	return $_[0]->{onNameChange};
}

##
# CallbackList $Actor->onUpdate()
# Ensures: defined(result)
#
# Returns the onUpdate event callback list.
sub onUpdate {
	return $_[0]->{onUpdate};
}

1;
