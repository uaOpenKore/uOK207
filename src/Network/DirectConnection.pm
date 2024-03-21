#########################################################################
#  OpenKore - Networking subsystem
#  This module contains functions for sending packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 5249 $
#  $Id: Network.pm 5249 2006-12-25 14:40:58Z vcl_kore $
#
#########################################################################
##
# MODULE DESCRIPTION: Connection handling
#
# The Network module handles connections to the Ragnarok Online server.
# This module only handles connection issues, and nothing else. It doesn't do
# anything with the actual data. Network data handling is performed by
# the @MODULE(Network::Receive) and Network::Receive::ServerTypeX classes.
#
# The submodule @MODULE(Network::Send) contains functions for sending all
# kinds of messages to the RO server.
#
# Please also read <a href="http://www.openkore.com/wiki/index.php/Network_subsystem">the
# network subsystem overview.</a>
#
# This implementation establishes a direct connection to the RO server.
# Note that there are alternative implementations for this interface: @MODULE(Network::XKore),
# @MODULE(Network::XKore2) and @MODULE(Network::XKoreProxy)

package Network::DirectConnection;

use strict;
use Modules 'register';
use Exporter;
use base qw(Exporter);
use Time::HiRes qw(time);
use IO::Socket::INET;
use encoding 'utf8';
use Scalar::Util;
use File::Spec;

use Globals;
use Log qw(message error);
use Network;
use Network::Send ();
use Plugins;
use Settings;
use Interface;
use Utils qw(dataWaiting timeOut);
use Utils::Exceptions;
use Misc qw(chatLog);
use Translation;

##
# Network::DirectConnection->new([wrapper])
# wrapper: If this object is to be wrapped by another object which is interface-compatible
#          with the Network::DirectConnection class, then specify the wrapper object here. The message
#          sender will use this wrapper to send socket data. Internally, the reference to the wrapper
#          will be stored as a weak reference.
#
# Create a new Network::DirectConnection object. The connection is not yet established.
sub new {
	my ($class, $wrapper) = @_;
	my %self;

	$self{remote_socket} = new IO::Socket::INET;
	if ($wrapper) {
		$self{wrapper} = $wrapper;
		Scalar::Util::weaken($self{wrapper});
	}

	return bless \%self, $class;
}

##
# int $net->version()
#
# Returns the implementation number this object.
sub version {
	return 0;
}

sub DESTROY {
	my $self = shift;
	
	$self->serverDisconnect();
}


######################
## Server Functions ##
######################

##
# boolean $net->serverAliveServer()
#
# Check whether the connection to the server is alive.
sub serverAlive {
	return $_[0]->{remote_socket} && $_[0]->{remote_socket}->connected();
}

##
# String $net->serverPeerHost()
#
# If the connection to the server is alive, returns the host name of the server.
# Otherwise, returns undef.
sub serverPeerHost {
	return $_[0]->{remote_socket}->peerhost if ($_[0]->serverAlive);
	return undef;
}

##
# int $net->serverPeerPort()
#
# If the connection to the server is alive, returns the port number of the server.
# Otherwise, returns undef.
sub serverPeerPort {
	return $_[0]->{remote_socket}->peerport if ($_[0]->serverAlive);
	return undef;
}

##
# $net->serverConnect(String host, int port)
# host: the host name/IP of the RO server to connect to.
# port: the port number of the RO server to connect to.
#
# Establish a connection to a Ragnarok Online server.
#
# This function is used internally by $net->checkConnection() and should not be used directly.
sub serverConnect {
	my $self = shift;
	my $host = shift;
	my $port = shift;
	my $return = 0;

	Plugins::callHook('Network::connectTo', {
		socket => \$self->{remote_socket},
		return => \$return,
		host => $host,
		port => $port
	});
	return if ($return);

	message TF("Connecting (%s:%s)... ", $host, $port), "connection";
	$self->{remote_socket} = new IO::Socket::INET(
			LocalAddr	=> $config{bindIp} || undef,
			PeerAddr	=> $host,
			PeerPort	=> $port,
			Proto		=> 'tcp',
			Timeout		=> 4);
	($self->{remote_socket} && inet_aton($self->{remote_socket}->peerhost()) eq inet_aton($host)) ?
		message T("connected\n"), "connection" :
		error(TF("couldn't connect: %s (error code %d)\n", "$!", int($!)), "connection");
	if ($self->getState() != Network::NOT_CONNECTED) {
		$incomingMessages->nextMessageMightBeAccountID();
	}
}

##
# void $net->serverSend(Bytes data)
#
# If the connection to the server is alive, send data to the server.
# Otherwise, this method does nothing.
sub serverSend {
	my $self = shift;
	my $msg = shift;
	if ($self->serverAlive) {
		if (Plugins::hasHook("Network::serverSend/pre")) {
			Plugins::callHook("Network::serverSend/pre", { msg => \$msg });
		}
		if (defined $msg) {
			$self->{remote_socket}->send($msg);
			if (Plugins::hasHook("Network::serverSend")) {
				Plugins::callHook("Network::serverSend", { msg => $msg });
			}
		}
	}
}

##
# Bytes $net->serverRecv()
#
# Receive data from the RO server.
sub serverRecv {
	my $self = shift;
	my $msg;
	
	return undef unless (dataWaiting(\$self->{remote_socket}));
	
	$self->{remote_socket}->recv($msg, 1024 * 32);
	if (Plugins::hasHook("Network::serverRecv")) {
		Plugins::callHook("Network::serverRecv", { msg => \$msg });
	}
	if (!defined($msg) || length($msg) == 0) {
		# Connection from server closed.
		close($self->{remote_socket});
		return undef;
	}
	return $msg;
}

##
# Bytes $net->serverAddress()
#
# Return the server's raw address.
sub serverAddress {
	my ($self) = @_;
	return $self->{remote_socket}->sockaddr();
}

##
# $net->serverDisconnect()
#
# Disconnect from the current Ragnarok Online server.
#
# This function is used internally by $net->checkConnection() and should not be used directly.
sub serverDisconnect {
	my $self = shift;
	
	if ($self->serverAlive) {
		$messageSender->sendQuit() if ($self->getState() == Network::IN_GAME);

		message TF("Disconnecting (%s:%s)...", $self->{remote_socket}->peerhost(), 
			$self->{remote_socket}->peerport()), "connection";
		close($self->{remote_socket});
		!$self->serverAlive() ?
			message T("disconnected\n"), "connection" :
			error T("couldn't disconnect\n"), "connection";
	}
}

sub getState {
	return $conState;
}

sub setState {
	my ($self, $state) = @_;
	$conState = $state;
	Plugins::callHook('Network::stateChanged');
}


######################
## Client Functions ##
######################

##
# boolean $net->clientAlive()
#
# Check whether there are one or more clients connected to Kore.
sub clientAlive {
	my %args = (net => $_[0]);
	Plugins::callHook('Network::clientAlive', \%args);
	return $args{return};
}

##
# $net->clientSend(Bytes data)
#
# Make the RO client think that it has received $data.
sub clientSend {
	my ($self) = @_;
	if ($self->clientAlive && Plugins::hasHook('Network::clientSend')) {
		my %args = (net => $self, data => $_[1]);
		Plugins::callHook('Network::clientSend', \%args);
		return $args{return};
	} else {
		return undef;
	}
}

##
# Bytes $net->clientRecv()
#
# Receive data that the RO client wants to send to the RO server.
sub clientRecv {
	my ($self) = @_;
	if ($self->clientAlive) {
		my %args = (net => $_[0]);
		Plugins::callHook('Network::clientRecv', \%args);
		return $args{return};
	} else {
		return undef;
	}
}


#######################
## Utility Functions ##
#######################

#######################################
#######################################
# Check Connection
#######################################
#######################################

##
# $net->checkConnection()
#
# Handles any connection issues. Based on the current situation, this function may
# re-connect to the RO server, disconnect, do nothing, etc.
#
# This function is meant to be run in the Kore main loop.
sub checkConnection {
	my $self = shift;
	
	return if ($Settings::no_connect);

	if ($self->getState() == Network::NOT_CONNECTED && (!$self->{remote_socket} || !$self->{remote_socket}->connected) && timeOut($timeout_ex{'master'}) && !$conState_tries) {
		my $master = $masterServer = $masterServers{$config{master}};

		foreach my $serverOption ('serverType', 'chatLangCode', 'storageEncryptKey', 'gameGuard', 'charBlockSize',
					'paddedPackets', 'paddedPackets_attackID', 'paddedPackets_skillUseID',
					'mapServer_ip', 'mapServer_port') {
			if ($master->{$serverOption} ne '' && $config{$serverOption} ne $master->{$serverOption}) {
				main::configModify($serverOption, $master->{$serverOption});
			}
		}
		if ($master->{serverEncoding} ne '' && $config{serverEncoding} ne $master->{serverEncoding}) {
			main::configModify('serverEncoding', $master->{serverEncoding});
		} elsif ($config{serverEncoding} eq '') {
			main::configModify('serverEncoding', 'Western');
		}
		if (Settings::setRecvPacketsName($masterServer->{recvpackets})) {
			my (undef, undef, $basename) = File::Spec->splitpath(Settings::getRecvPacketsFilename());
			Settings::loadByRegexp(quotemeta $basename, sub {
				my ($filename) = @_;
				message TF("Loading %s...\n", $filename);
			});
		}

		message T("Connecting to Account Server...\n", "connection");
		$shopstarted = 1;
		$conState_tries++;
		$initSync = 1;
		$incomingMessages->clear();

		eval {
			$packetParser = Network::Receive->create($config{serverType});
			my $wrapper = ($self->{wrapper}) ? $self->{wrapper} : $self;
			$messageSender = Network::Send->create($wrapper, $config{serverType});
		};
		if ($@) {
			$interface->errorDialog("$@");
			$quit = 1;
			return;
		}
		$reconnectCount++;
		$self->serverConnect($master->{ip}, $master->{port});

		# call plugin's hook to determine if we can continue the work
		if ($self->serverAlive) {
			Plugins::callHook("Network::serverConnect/master");
			return if ($conState == 1.5);
		}

		# GameGuard support
		if ($self->serverAlive && $config{gameGuard} == 2) {
			my $msg = pack("C*", 0x58, 0x02);
			$net->serverSend($msg);
			message T("Requesting permission to logon on account server...\n");
			$conState = 1.2;
			return;
		}

		if ($self->serverAlive && $master->{secureLogin} >= 1) {
			my $code;

			message T("Secure Login...\n"), "connection";
			undef $secureLoginKey;

			if ($master->{secureLogin_requestCode} ne '') {
				$code = $master->{secureLogin_requestCode};
			} elsif ($config{secureLogin_requestCode} ne '') {
				$code = $config{secureLogin_requestCode};
			}

			if ($code ne '') {
				$messageSender->sendMasterCodeRequest('code', $code);
			} else {
				$messageSender->sendMasterCodeRequest('type', $master->{secureLogin_type});
			}

		} elsif ($self->serverAlive) {
			$messageSender->sendPreLoginCode($master->{preLoginCode}) if ($master->{preLoginCode});
			$messageSender->sendMasterLogin($config{'username'}, $config{'password'},
				$master->{master_version}, $master->{version});
		}

		$timeout{'master'}{'time'} = time;

	# we skipped some required connection operations while waiting for the server to allow as to login,
	# after we have successfully sent in the reply to the game guard challenge (using the poseidon server)
	# this conState will allow us to continue from where we left off.
	} elsif ($conState == 1.3) {
		$conState = 1;
		my $master = $masterServer = $masterServers{$config{'master'}};
		if ($master->{secureLogin} >= 1) {
			my $code;

			message T("Secure Login...\n"), "connection";
			undef $secureLoginKey;

			if ($master->{secureLogin_requestCode} ne '') {
				$code = $master->{secureLogin_requestCode};
			} elsif ($config{secureLogin_requestCode} ne '') {
 				$code = $config{secureLogin_requestCode};
			}

			if ($code ne '') {
				$messageSender->sendMasterCodeRequest('code', $code);
			} else {
				$messageSender->sendMasterCodeRequest('type', $master->{secureLogin_type});
			}

		} else {
			$messageSender->sendPreLoginCode($master->{preLoginCode}) if ($master->{preLoginCode});
			$messageSender->sendMasterLogin($config{'username'}, $config{'password'},
				$master->{master_version}, $master->{version});
		}

		$timeout{'master'}{'time'} = time;
		
	} elsif ($conState == 1 && $masterServer->{secureLogin} >= 1 && $secureLoginKey ne ""
	   && !timeOut($timeout{'master'}) && $conState_tries) {

		my $master = $masterServer;
		message T("Sending encoded password...\n"), "connection";
		$messageSender->sendMasterSecureLogin($config{'username'}, $config{'password'}, $secureLoginKey,
				$master->{version}, $master->{master_version},
				$master->{secureLogin}, $master->{secureLogin_account});
		undef $secureLoginKey;

	} elsif ($conState == 1 && timeOut($timeout{'master'}) && timeOut($timeout_ex{'master'})) {
		if ($config{dcOnMaxReconnections} && $config{dcOnMaxReconnections} <= $reconnectCount) {
			$quit = 1;
			return;
		}
		error T("Timeout on Account Server, reconnecting...\n"), "connection";
		$timeout_ex{'master'}{'time'} = time;
		$timeout_ex{'master'}{'timeout'} = $timeout{'reconnect'}{'timeout'};
		$self->serverDisconnect;
		undef $conState_tries;

	} elsif ($conState == 1.5) {
		
		if (!$self->serverAlive) {
			$self->setState(Network::NOT_CONNECTED);
			undef $conState_tries;
			return;
		}
		
		# on this special stage, the plugin will know what to do next.
		Plugins::callHook("Network::serverConnect/special");
		
	} elsif ($conState == 2 && !$self->serverAlive()
	  && ($config{'server'} ne "" || $masterServer->{charServer_ip})
	  && !$conState_tries) {
		if ($config{pauseCharServer}) {
			message "Pausing for $config{pauseCharServer} second(s)...\n", "system";
			sleep $config{pauseCharServer};
		}
		my $master = $masterServer;
		message T("Connecting to Character Server...\n"), "connection";
		$conState_tries++;

		if ($master->{charServer_ip}) {
			$self->serverConnect($master->{charServer_ip}, $master->{charServer_port});
		} elsif ($servers[$config{'server'}]) {
			$self->serverConnect($servers[$config{'server'}]{'ip'}, $servers[$config{'server'}]{'port'});
		} else {
			error TF("Invalid server specified, server %s does not exist...\n", $config{server}), "connection";

			my @serverList;
			foreach my $server (@servers) {
				push @serverList, $server->{name};
			}
			my $ret = $interface->showMenu(
					T("Please select your login server."),
					\@serverList,
					title => T("Select Login Server"));
			if ($ret == -1) {
				quit();
			} else {
				main::configModify('server', $ret, 1);
				undef $conState_tries;
			}
			return;
		}

		# call plugin's hook to determine if we can continue the connection
		if ($self->serverAlive) {
			Plugins::callHook("Network::serverConnect/char");
			$reconnectCount = 0;
			return if ($conState == 1.5);
		}
		
		$messageSender->sendGameLogin($accountID, $sessionID, $sessionID2, $accountSex);
		$timeout{'gamelogin'}{'time'} = time;

	} elsif ($conState == 2 && timeOut($timeout{'gamelogin'})
	  && ($config{'server'} ne "" || $masterServer->{'charServer_ip'})) {
		error T("Timeout on Character Server, reconnecting...\n"), "connection";
		$timeout_ex{'master'}{'time'} = time;
		$timeout_ex{'master'}{'timeout'} = $timeout{'reconnect'}{'timeout'};
		$self->serverDisconnect;
		undef $conState_tries;
		$self->setState(Network::NOT_CONNECTED);

	} elsif ($conState == 3 && !$self->serverAlive() && $config{'char'} ne "" && !$conState_tries) {
		message T("Connecting to Character Select Server...\n"), "connection";
		$conState_tries++;
		$self->serverConnect($servers[$config{'server'}]{'ip'}, $servers[$config{'server'}]{'port'});

		# call plugin's hook to determine if we can continue the connection
		if ($self->serverAlive) {
			Plugins::callHook("Network::serverConnect/charselect");
			return if ($conState == 1.5);
		}
				
		$messageSender->sendCharLogin($config{'char'});
		$timeout{'charlogin'}{'time'} = time;

	} elsif ($conState == 3 && timeOut($timeout{'charlogin'}) && $config{'char'} ne "") {
		error T("Timeout on Character Select Server, reconnecting...\n"), "connection";
		$timeout_ex{'master'}{'time'} = time;
		$timeout_ex{'master'}{'timeout'} = $timeout{'reconnect'}{'timeout'};
		$self->serverDisconnect;
		$self->setState(Network::NOT_CONNECTED);
		undef $conState_tries;

	} elsif ($conState == 4 && !$self->serverAlive() && !$conState_tries) {
		if ($config{pauseMapServer}) {
			message "Pausing for $config{pauseMapServer} second(s)...\n", "system";
			sleep($config{pauseMapServer});
		}
		message T("Connecting to Map Server...\n"), "connection";
		$conState_tries++;
		main::initConnectVars();
		my $master = $masterServer;
		my ($ip, $port);
		if ($master->{private}) {
			$ip = $config{forceMapIP} || $master->{ip};
			$port = $map_port;
		} else {
			$ip = $master->{mapServer_ip} || $config{forceMapIP} || $map_ip;
			$port = $master->{mapServer_port} || $map_port;
		}
		$self->serverConnect($ip, $port);

		# call plugin's hook to determine if we can continue the connection
		if ($self->serverAlive) {
			Plugins::callHook("Network::serverConnect/mapserver");
			return if ($conState == 1.5);
		}

		$messageSender->sendMapLogin($accountID, $charID, $sessionID, $accountSex2);
		$timeout_ex{master}{time} = time;
		$timeout_ex{master}{timeout} = $timeout{reconnect}{timeout};
		$timeout{maplogin}{time} = time;

	} elsif ($conState == 4 && timeOut($timeout{maplogin})) {
		message T("Timeout on Map Server, connecting to Account Server...\n"), "connection";
		$timeout_ex{master}{timeout} = $timeout{reconnect}{timeout};
		$self->serverDisconnect;
		$self->setState(Network::NOT_CONNECTED);
		undef $conState_tries;

	} elsif ($conState == 5 && !$self->serverAlive()) {
		Plugins::callHook('disconnected');
		if ($config{dcOnDisconnect}) {
			chatLog("k", T("*** You disconnected, auto quit! ***\n"));
			error T("Disconnected from Map Server, exiting...\n"), "connection";
			$quit = 1;
		} else {
			error TF("Disconnected from Map Server, connecting to Account Server in %s seconds...\n", $timeout{reconnect}{timeout}), "connection";
			$timeout_ex{master}{time} = time;
			$timeout_ex{master}{timeout} = $timeout{reconnect}{timeout};
			$self->setState(Network::NOT_CONNECTED);
			undef $conState_tries;
		}

	} elsif ($conState == 5 && timeOut($timeout{play})) {
		error T("Timeout on Map Server, "), "connection";
		Plugins::callHook('disconnected');
		if ($config{dcOnDisconnect}) {
			error T("exiting...\n"), "connection";
			$quit = 1;
		} else {
			error TF("connecting to Account Server in %s seconds...\n", $timeout{reconnect}{timeout}), "connection";
			$timeout_ex{master}{time} = time;
			$timeout_ex{master}{timeout} = $timeout{reconnect}{timeout};
			$self->serverDisconnect;
			$self->setState(Network::NOT_CONNECTED);
			undef $conState_tries;
		}
	}
}

return 1;
