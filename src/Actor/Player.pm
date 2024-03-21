#########################################################################
#  OpenKore - Player actor object
#  Copyright (c) 2005 OpenKore Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 6763 $
#  $Id: Player.pm 6763 2009-07-08 16:42:59Z eternalharvest $
#
#########################################################################
##
# MODULE DESCRIPTION: Player actor object
#
# All members in %players are of the Actor::Player class.
#
# @MODULE(Actor) is the base class for this class.
package Actor::Player;

use strict;
use Actor;
use Globals;
use base qw(Actor);

sub new {
	my ($class, $type) = @_;
	return $class->SUPER::new('Player');
}

sub selfString {
	my ($self) = @_;

	return $self->{sex} ? 'himself' : 'herself';
}

##
# String $ActorPlayer->job()
#
# Returns the job string (e.g. "Knight") of the actor.
sub job {
	my ($self) = @_;

	return $jobs_lut{$self->{jobID}};
}

1;
