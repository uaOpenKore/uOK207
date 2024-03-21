#!/usr/bin/env perl
#########################################################################
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#########################################################################

package autoupdate;
use strict;
use FindBin qw($RealBin);
use lib "$RealBin";
use lib "$RealBin/src";
use lib "$RealBin/src/deps";

use Time::HiRes qw(time usleep);
use Carp::Assert;

# Update base
use SVN::Updater;

sub check_svn_util {
	my $saa = SVN::Updater->new({ path => "."});
	if ($saa->_svn_command("help") == -1) {
		print "Warning!!!!!!!!!!! To use this tool please Install \"Subversion Client\" tools\n";
		sleep (60000);
		return -1;
	};
	return 1;
};

sub upgrade {
	my ($path, $repos_name) = @_;
	print "Chenking " . $repos_name . " for updates...\n";
	my $sa = SVN::Updater->load({ path => $path });

	print "  Fetching updates...\n";
	$sa->update("--force", "--accept theirs-conflict");
	print " Done updating " . $repos_name . "\n";
};

print "-===================== OpenKore Auto Update tool =====================-\n";
if (check_svn_util() == 1) {
	upgrade(".", "OpenKore core files") if (-d "src/.svn");
	upgrade("./tables", "OpenKore table data files") if (-d "tables/.svn");
	upgrade("./fields", "OpenKore map data files") if (-d "fields/.svn");
};
print "-=========================== Done Updating ===========================-\n\n\n";

# Run main App
my $file = "openkore.pl";
$0 = $file;
FindBin::again();
{
	package main;
	do $file;
}

1;
