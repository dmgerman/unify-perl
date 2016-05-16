#!/usr/bin/perl

###
#
#
# query to get the most common authors
#select author, count(*), count(*)*1.0/(select count(*) from blame where filename regexp '\.py$') as  p from blame where filename regexp '\.py$' group by author order by count(*) desc limit 20;
#



use DBI;
use strict;

my $dbName = shift @ARGV;


die "It should be run from root dir of git" unless -d ".git";

die "$0 <dbname>" unless $dbName ne "";

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbName", "", "", { RaiseError => 1,   AutoCommit => 0 }) or die $DBI::errstr;

$dbh->do("drop table if exists blame;");

$dbh->do("CREATE TABLE blame (cid char(40), author varchar(100), authormail varchar(100), authortime int, authortz   char(10), filename  text, filename2  text, ttype     varchar(100), value     text, value2    text);");

my $sth = $dbh->prepare("insert into blame(cid,author,authormail,authortime,authortz,filename,filename2,ttype,value, value2) values (?,?,?,?,?,?,?,?,?,?)");

open(IN, "git ls-files |" );
#open(IN, "find . -type f | " );
#open(IN, "find . -type f |");

my @files = <IN>;

close IN;

foreach my $f (@files) {
    chomp $f;
    print "$f\n";
    Blame($f);
}

$dbh->disconnect();

sub Blame {
    my ($filename) = @_;


    open(B, "git blame --line-porcelain '$filename'|") or die "Unable to run blame on [$filename]";
    while (my %f = Read_Record()) {
        if (scalar(%f) > 0) {
            #            print "$f;$f{cid};$f{author};$f{ttype};$f{value};$f{value2}\n";

            $sth->execute($f{"cid"}, $f{"author"}, $f{"author-mail"}, $f{"author-time"}, $f{"author-tz"}, $filename, $f{"filename"}, $f{"ttype"}, $f{"value"}, $f{"value2"});
        }
    }
    $dbh->commit();
}


sub Read_Record {
    my %f ;
    
    my $temp = <B>;
    
    return %f unless defined $temp;
    chomp $temp;
    $temp =~ s/^([0-9a-f]{40}) .*$/$1/;
    die "illegal record begin $_" unless $1 ne "";
    $f{cid} = $temp;
    
    while (<B>) {
	chomp;
        if (/^	(.*)$/)  {
            my $temp = $1;
            # see if there is a separator
            if ($temp =~ /^(DECL)\|([^\|]+)\|(.+)$/) {
                $f{"ttype"} = $1;
                $f{"value"} = $2;
                $f{"value2"} = $3;
            } elsif ($temp =~ /^([a-z_]+)\|(.+)/) {
                $f{"ttype"} = $1;
                $f{"value"} = $2;
            } else {
                $f{"ttype"} = $temp;
            }
            return %f;
        } else {
            if (/^([^ ]+) (.*)$/) {
                $f{$1} = $2;
            } elsif (/^boundary$/) {
            } else {
                die "Illegal record [$_]"
            }
        }
    }
    return %f;
}
