#  kRO Client 2008-3-26 (eA packet version 9)
# Servertype overview: http://www.openkore.com/wiki/index.php/ServerType
package Network::Receive::ServerType8_4;

use strict;
use Network::Receive;
use base qw(Network::Receive);

sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new;
	
	$self->{packet_list}{'0078'} = ['actor_display', 'x1 a4 v14 a4 x7 C1 a3 x2 C1 v1', [qw(ID walk_speed param1 param2 param3 type hair_style weapon lowhead shield tophead midhead hair_color clothes_color head_dir guildID sex coords act lv)]];
	$self->{packet_list}{'007C'} = ['actor_display', 'x1 a4 v1 v1 v1 v1 x6 v1 C1 x12 C1 a3', [qw(ID walk_speed param1 param2 param3 type pet sex coords)]],
	$self->{packet_list}{'022C'} = ['actor_display', 'x1 a4 v4 x2 v5 V1 v3 x4 a4 a4 v x2 C2 a5 x3 v', [qw(ID walk_speed param1 param2 param3 type hair_style weapon shield lowhead timestamp tophead midhead hair_color guildID guildEmblem visual_effects stance sex coords lv)]],

	return $self;
}

# Overrided method.
sub received_characters_blockSize {
	return 108;
}

1;
