#########################################################################
#  OpenKore - Network subsystem
#  Copyright (c) 2006 OpenKore Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
# idRO (Indonesia)
# Servertype overview: http://www.openkore.com/wiki/index.php/ServerType
package Network::Receive::ServerType22;

use strict;
use Network::Receive;
use base qw(Network::Receive);
use Log qw(message warning error debug);
use Translation;
use Globals;
use Plugins;
use Misc;
use I18N qw(bytesToString);
use Utils qw(getHex swrite makeIP makeCoords);

sub new {
   my ($class) = @_;
   my $self = $class->SUPER::new();

   $self->{packet_list}{'0078'} = ['actor_display', 'x1 a4 v14 a4 v2 x2 C2 a3 x2 C1 v1', [qw(ID walk_speed param1 param2 param3 type hair_style weapon shield lowhead tophead midhead hair_color clothes_color head_dir guildID guildEmblem visual_effects stance sex coords act lv)]];
   $self->{packet_list}{'007C'} = ['actor_display', 'x1 a4 v14 C2 a3', [qw(ID walk_speed param1 param2 param3 hair_style weapon lowhead type shield tophead midhead hair_color clothes_color head_dir stance sex coords)]];
   $self->{packet_list}{'022C'} = ['actor_display', 'x1 a4 v3 V1 v5 V1 v5 a4 a4 V1 C2 a5 x3 v1', [qw(ID walk_speed param1 param2 param3 type hair_style weapon shield lowhead timestamp tophead midhead hair_color clothes_color head_dir guildID guildEmblem visual_effects stance sex coords lv)]];
   $self->{packet_list}{'009A'} = ['system_chat', 'x2 A*', [qw(message)]];

   return $self;
}

sub system_chat {
   my ($self, $args) = @_;

   my $message = bytesToString($args->{message});
   if (substr($message,0,4) eq 'micc') {
      $message = bytesToString(substr($args->{message},34));
   }
   stripLanguageCode(\$message);
   chatLog("s", "$message\n") if ($config{logSystemChat});
   # Translation Comment: System/GM chat
   message TF("[GM] %s\n", $message), "schat";
   ChatQueue::add('gm', undef, undef, $message);

   Plugins::callHook('packet_sysMsg', {
      Msg => $message
   });
}


1;