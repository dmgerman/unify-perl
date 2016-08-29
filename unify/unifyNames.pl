#!/usr/bin/perl

# how to generate the output
# git log --pretty=fuller | egrep '^(Commit|Author):' | perl -pe 's/^(Author|Commit):\s+//' | head  > /tmp/people 

use utf8;
use Text::Unaccent;



#use DBI;


# let us do it again. 
# we will take two files as input.
# the first is 
# <alias>;<id>
# the has the same format, but if the <id> is not present, then 
# consider the <id> the same

require Set::Scalar;

use strict;

my $debug = 0;
my $indentedOutput = 0;

# let us use three files, some potentially empty

# names
# ignore names
# aliased


my $ignoreFile = shift;
my $newAuthorsFile = shift;
my $knownFile = shift;

if ($ignoreFile eq "" or
    $newAuthorsFile eq "" or
    $knownFile eq ""
   ) {
    die "$0 <ignoreFile> <newAuthors> <knownAuthors>"
}

my %alias2email;     # maps an alias to an email
my %alias2uniname;   # maps an alias to its unified name
my %aliasComponents;# maps an alias to its components [name, email, username, domain]
my %sets;           # sets of unified aliases. Key is the uniname, values are the sets of aliases that correspond to this uniname
my %setsNames;
my %aliasCount ;    # how many times a given alias has been seen

#read them and create a unification by email address
my $i=0;

my %ignore = Read_Ignore($ignoreFile);

open(IN, "<$newAuthorsFile") or die "unable to open file with new authors [$newAuthorsFile]";

my $skipped;
while (<IN>) {
    chomp;
    my $alias = $_;
    my $aliasToSplit = $alias;

    if ($alias =~ /<>/ 
	or ($alias =~ /<set EMAIL_ADDRESS environment variable>/)
	or ($ignore{$alias} ne "")
	) {
	$skipped ++;
	print STDERR "Skipping [$alias]\n" if $debug;
	next ;
    }
#    if ($alias =~ /^([a-z]+) <([a-z]+)>$/) {
#	if ($1 eq $2) {
#	    $aliasToSplit ="$1 <$1\@src.gnome.org>";
#	}
#    }

    # count it
    if (defined($aliasCount{$alias})) {
	$aliasCount{$alias}++;
	next;
    } else {
	$aliasCount{$alias} = 1;
    }
    my ($name, $email, $username, $domain) = Split_Email($aliasToSplit);
    if (not defined($email)) {
	die "Illegal record [$alias]\n";
    }

    $alias2email{$alias} = $email;
    $aliasComponents{$alias} = [$name, $email, $username, $domain];
    # set contains 

    my $uniname = $email;

    if (defined($sets{$uniname})) {
	$sets{$uniname}->insert($alias);
    } else {
	$sets{$uniname} = Set::Scalar->new($alias);
    }
    $alias2uniname{$alias} = $uniname;
    $i++;
}
close IN;
print STDERR "Read [$i] commits [$skipped]  skipped  ", scalar(keys(%sets)), " different addresses\n";

Process_Names();

#foreach my $k (sort keys %setsNames) {
#    print "$k", $setsNames{$k}, "\n";
#}
#exit(0);
Unify_Sets();
#Process_Names();
#Unify_Sets();

Sub_Domains();
Unify_Sets();

Print_Alias();
exit(0);

sub Sub_Domains
{
# so we have read them. At this point they are unified by _IDENTICAL_ email address...
# now let us process their names and unify those names that are the same
    foreach my $alias (sort keys %aliasComponents) {
	my $domain = $aliasComponents{$alias}[3];
	my $user = $aliasComponents{$alias}[2];
	my $subdomain;
	if ($domain =~ /([^.]+\.[^.]+)$/) {
	    $subdomain = "$1";
	} else {
	    next;
	}

	# now, check the domain is long enough or it ends in a digraph
	if (length($subdomain) <= 5 or ($subdomain=~ /\.[^.]{2}$/) or ($subdomain =~ /dyndns\.org/)) {
	    next;
	}
	$subdomain = $user . "@" . $subdomain;
	
	# names need a space in between, otherwise it is just one name and will create collisions
	if (defined($setsNames{$subdomain})) {
#	    print "Added: $subdomain, $alias to [$subdomain] <" . $setsNames{$subdomain} . ">\n" ;
	    $setsNames{$subdomain}->insert($alias);
	} else {
	    $setsNames{$subdomain} = Set::Scalar->new($alias);	
	}
    }
}

sub Process_Names
{
# so we have read them. At this point they are unified by _IDENTICAL_ email address...
# now let us process their names and unify those names that are the same
    foreach my $alias (sort keys %aliasComponents) {
	my $name = $aliasComponents{$alias}[0];
	
	# names need a space in between, otherwise it is just one name and will create collisions
	if ($name =~ /. ./) {
	    if (defined($setsNames{$name})) {
		print STDERR "Added: $name, $alias to [$name] <" . $setsNames{$name} . ">\n"  if $debug;
		$setsNames{$name}->insert($alias);
	    } else {
		$setsNames{$name} = Set::Scalar->new($alias);	
	    }
	}
    }

}


sub Unify_Sets
{
    my %deleted;
# so now, if a set of names has more than one record, we unify both sets into one, using order as the name to use
    foreach my $k (sort keys %setsNames)  {
	print STDERR "Unify: $k\n" if $debug;
	my $set =$setsNames{$k};
	my @aliases = $set->elements;
	
	my $alias1 = pop(@aliases);
	while (scalar(@aliases) > 0) { 
	    my $alias2 = pop(@aliases);
	    
	    # we need to unify them
	    die "not first [$alias1]" unless defined $alias2uniname{$alias1};
	    die "not second [$alias2] " unless defined $alias2uniname{$alias2};
	    
	    # swamp them to we keep the most common alias always first
	    if ($aliasCount{$alias2} > $aliasCount{$alias1}) {
		my $temp = $alias2;
		$alias2 = $alias1;
		$alias1 = $temp;
	    }
	    my $uni1 = $alias2uniname{$alias1};
	    my $uni2 = $alias2uniname{$alias2};
	    
	    if ($uni1 eq $uni2) {
		# they are the same, no need to merge
		print STDERR "Same [$alias1][$alias2][$uni1][$uni2]\n" if $debug;
		next;
	    }
	    
	    # we might have deleted in a previous pass
	    if (defined $deleted{$uni1}) {
		print STDERR ">$uni1;$uni2\n" if $debug;
		$uni1 = $deleted{$uni1};
		print STDERR "$uni1\n" if $debug;
		die;
	    }
	    if (defined $deleted{$uni2}) {
		$uni2 = $deleted{$uni2};
	    }
	    
	    die "not defined first uni [$uni1]" unless defined $sets{$uni1};
	    die "not defined second uni [$uni2] " unless defined $sets{$uni2};
	    
	    print STDERR "Merging [$alias1][$uni1] with [$alias2][$uni2]\n" if $debug;
	    $sets{$uni1} = $sets{$uni1}->union($sets{$uni2});
	    
	    # now reset the uninames of the alias in the second set
	    foreach my $alias ($sets{$uni2}->elements) {
		$alias2uniname{$alias} = $uni1;
	    }
	    
	    $sets{$uni2}->clear();
	    delete($sets{$uni2});
	    
	    $deleted{$uni2} = $uni1;
	}
    }
}






sub Print_Alias
{
#ok, so how many sets..
#    my $ins = $dbh->prepare("insert into aliases(alias, uniname) values (?, ?)");

    foreach my $k (sort keys %sets) {
	my @aliases = $sets{$k}->elements;
        
        my @sorted = sort {$aliasCount{$b} <=>  $aliasCount{$a}} @aliases;
        
        my $key = $aliasComponents{$sorted[0]}[0];

        if ($indentedOutput) {
            print "$key\n";
            foreach my $e (@sorted) {
                print "\t$aliasCount{$e}\n";
            }
        } else {
            foreach my $e (@sorted) {
                print "$key;$e;$aliasCount{$e}\n";
            }
        }

#	print "$k: ", $sets{$k}, "\n";
#	foreach my $a (@aliases) {
# $ins->execute($a, $k);
#	}
    }
}

sub Split_Email
{
    my ($email) = @_;

#    $email =~ s/\*\* ISO-8859-1 charset \*\*\//;
#    $email =~ s/á/á/g;
#    $email =~s/�/a/g;
   
    my $m1;
    my $m2;
    if ($email =~ /^(.+)@(.+) <>$/) {
	$email = "$1 <$1\@$2>";
    }
    die "illegal [$email]" unless $email =~ /^(.*)\s*<([^>]+)>$/;

    my ($name, $b) = ($1, $2);
    $name =~ s/\s+$//;

    die "[$name]" if $name =~ / $/;

    $name = lc($name);
    my $temp = unac_string('UTF-8', $name);

    if ($temp eq "") {
        $temp = unac_string('LATIN1', $name);
    }
    if ($temp eq "") {
        $temp = unac_string('UTF-16', $name);
    }

    $name = $temp if ($temp ne ""); # converstion did not failed
     
    # lowercase the email
    $b = lc($b);



    # if the name has a comma, invert it
    if ($name =~ /^(.+),\s+(.+)$/) {
	$name = $2 . " " . $1;
    }
    # if name has a X. in between remove it
    # the period after is optional
    if ($name =~ /^(..+) .\.? (...+)$/) {
	$name = $1 . " " . $2;
    }

    if ($name =~ /\-/) {
#	print ">>$name\n";
    }

    if ($b eq "") {
	$b = $name;
    }

#    $b =~ lc(quotemeta($b));

    if ($b =~ /^([^@]+)@(.+)$/) {
        $m1 = $1;
        $m2 = $2;
    } else {
	$m1 = $b;
    }
    if ($name eq "") {
	$name = $m1;
    }

    return ($name, $b, $m1, $m2);
}

sub Read_Ignore
{
    my ($file) = @_;
    open(IN, "<$file") or die "unable to open ignore file [$file]";
    
    my %ignore;
    while (<IN> ) {
        chomp;
        my $alias = $_;
        $ignore{$alias} = $alias;
        print STDERR "Ignoring [$alias]\n"  if $debug;
    }
    close IN;
}
