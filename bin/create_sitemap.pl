#!/usr/bin/env perl
# Patrick.Hochstenbach@UGent.be
use Catmandu::Sane;
use Catmandu;
use Catmandu::Fix;
use Data::Dumper;
use Getopt::Long;

Catmandu->load;

my $help          = undef;
my $verbose       = undef;
my $outdir        = undef;
my $maxurl        = Catmandu->config->{maxurl};
my $maxsize       = Catmandu->config->{maxsize};
my $query         = Catmandu->config->{query} // '*:*';
my $filetemplate  = Catmandu->config->{filetemplate} // 'sitemap%d.xml';
my $indextemplate = Catmandu->config->{indextemplate} // 'sitemap_index.xml';
my $baseurl       = Catmandu->config->{baseurl} // 'http://localhost';
my $changefreq    = Catmandu->config->{sitemap}->{changefreq} // 'yearly';
my $priority      = Catmandu->config->{sitemap}->{priority}   // '0.5';
my $lastmod       = Catmandu->config->{sitemap}->{lastmod};
my $fixes         = Catmandu->config->{fixes} // [];

GetOptions("v" => \$verbose , "q=s" => \$query , 
           "n=i" => \$maxurl , "S=i" => \$maxsize , 
           "p=f" => \$priority , "c=s" => \$changefreq ,
           "f=s" => \$filetemplate, "i=s" => \$indextemplate , "o=s" => \$outdir ,
           "base=s" => \$baseurl, "h" => \$help);
          
die "failed to open $outdir for writing" if (defined $outdir && ! -w $outdir);

if ($help) {
    print STDERR <<EOF;
usage: $0 [options]

options:
   -v             verbose
   -q STRING      query for 'STRING'
   -n NUM         maximum number of URLs in sitemap
   -S SIZE        maximum size of sitemap in bytes
   -p PRIORIY
   -c CHANGEFREQ
   -f TEMPLATE    template for nameing sitemap files e.g. sitemap-%3.3d.xml.gz
   -i TEMPLATE    template for nameing the sitemap index file e.g. sitemap_index.xml
   -o DIRECTORY   output directory
   --base URL     basurl for your index file
   -h             this help
   
example

   # Print sitemap to the STDOUT flush every 10 urls
   $0 -n 10
   
   # Print sitemap files into the current directory 
   $0 -v -n 10 -o .
   
EOF
    exit(1);
}

my $iterator = Catmandu::Fix->new(fixes => $fixes)->fix(Catmandu->store->bag->searcher(query => $query));

my $count = 0;
my $buffer = undef;    
$iterator->each(sub {
    $count++;
    
    my $obj = shift;
    $obj->{changefreq} //= $changefreq;
    $obj->{priority}   //= $priority;
    $obj->{lastmod}    //= $lastmod;
    
    if ($verbose && $count % 100 == 0) {
        print STDERR "$count...\n";
    }
    
    if ($count >= $maxurl) {
        $buffer .= &sitemap_footer;
        &serialize;
        $buffer = undef;
        $count  = 0;
    }
    elsif (defined $buffer && length $buffer >= $maxsize - 512) {
        $buffer .= &sitemap_footer;
        &serialize;
        $buffer = undef;
        $count  = 0;
    }
    elsif (!defined $buffer) {
        $buffer = &sitemap_header();
    }
    else {
        $buffer .= &sitemap_entry(%$obj);
    }
    
});

sub serialize {
    state $filecounter = 1;
    if ($outdir) {
        my $filename = sprintf $filetemplate , $filecounter;
        local(*F);
        print STDERR "creating $outdir/$filename...\n" if $verbose;
        my $writer = ($filename =~ /\.gz$/) ? "| gzip -c" : "";
        open(F,"$writer > $outdir/$filename") || die "failed to open $outdir/$filename for writing";
        print F $buffer;
        close(F);
        
        &update_index($filecounter);
        
        $filecounter++;
    }
    else {
        print $buffer;
    }
}

sub update_index {
    my $counter = shift;
    local(*F);
    
    print STDERR "Updating $outdir/$indextemplate...\n" if $verbose;
    open(F,">$outdir/$indextemplate");
    
    print F <<EOF;
<?xml version="1.0" encoding="UTF-8"?>

<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
EOF
    for (my $i = 1 ; $i <= $counter ; $i++) {
        my $filename = sprintf $filetemplate , $i;
        print F " <sitemap>\n";
        print F "  <loc>$baseurl/$filename</loc>\n";
        print F " </sitemap>\n";
    }
    
    print F <<EOF;
</sitemapindex>
EOF

    close(F);
}

sub sitemap_header {
    return <<EOF;
<?xml version="1.0" encoding="UTF-8"?>

<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
EOF
}

sub sitemap_entry {
    my (%args) = @_;
    my $str = "<url>\n";
    for (qw(loc lastmod changefreq priority)) {
        next unless exists $args{$_};
        $str .= "<$_>" . $args{$_} . "</$_>\n";
    }
    $str .= "</url>\n";
}

sub sitemap_footer {
    return <<EOF;
</urlset>
EOF
}
