package App::Dapper::Init;

=head1 NAME

App::Dapper::Init - Default project files to use when a "dapper init" command is used.

=head1 DESCRIPTION

When using the dapper tool to initialize an empty directory with a new site, the files
that are written to disk are contained in this file. For instance, the YAML project
file, a layout template, and a starter post.

=cut

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.8.0;
use strict;
use warnings FATAL => 'all';

use App::Dapper::Utils;

my $source_index_name = "index.md";
my $source_index_content = <<'SOURCE_INDEX_CONTENT';
---
layout: index
title: Welcome
---

Hello world.

SOURCE_INDEX_CONTENT

my $libs_name = "functions.pl";
my $libs_content = <<'LIBS_CONTENT';
print "IMPORTING LIBS functions.pl" . "\n";

sub save { my($key, $value) = @_;
	$stash->set($key, $value);
}

sub load { my($key) = @_;
	return $stash->get($key);
}

sub _varType { my($var) = @_;
  my $result = "";
  if(not ref($var)) {
    $result = "string";
  }
  elsif(ref($var) eq "HASH") {
    $result = "HASH";
  }
  elsif(ref($var) eq "ARRAY") {
    $result = "ARRAY";
  }
  elsif(ref($var) eq "SCALAR") {
    $result = "SCALAR";
  }
  elsif(ref($var) eq "CODE") {
    $result = "CODE";
  }
  elsif(ref($var) eq "REF") {
    $result = "REF";
  }
  elsif(ref($var) eq "VSTRING") {
    $result = "VSTRING";
  }
  elsif(ref($var) eq "Regexp") {
    $result = "Regexp";
  }
  elsif(ref($var) eq "GLOB") {
    $result = "GLOB";
  }
  elsif(ref($var) eq "LVALUE") {
    $result = "LVALUE";
  }
  elsif(ref($var) eq "FORMAT") {
    $result = "FORMAT";
  }
  elsif(ref($var) eq "IO") {
    $result = "IO";
  }
  return $result;
}

$stash->set('save', \&save);
$stash->set('load', \&load);
$stash->set('_varType', \&_varType);

#Add new custom functions here
LIBS_CONTENT




my $libs2_name = "pages.pl";
my $libs2_content = <<'LIBS2_CONTENT';
use strict;
use warnings;
use diagnostics;

use Data::Dumper;

print "IMPORTING LIBS pages.pl" . "\n";

sub getAllPages {
  my @result = ();
  @result = $stash->get('site')->{'pages'};
  @result = @{$result[0]};
  return @result;
}

sub getPathPage { my($page) = @_;
  my $result = "";
  $result = $page->{'dirname'};
  my $idx = index($result, '/');
  $result = substr($result, $idx);
  my $length = length($result);
  my $lastChar = substr($result, $length - 1);
  if ($lastChar eq '/' && $length > 1) {
    $result = substr($result, 0, $length - 1);
  }
  return $result;
}

sub loadInnerPages { my($parent) = @_;
  my @result = ();
  my $result2 = "";
  my $parentPath = getPathPage($parent);
  my @pages = getAllPages();
  my $pagesLength = @pages;
  $result2 = $pagesLength;
  for (my $i = 0; $i < $pagesLength; $i++) {
    my $cPage = $pages[$i];
    my $cPagePath = getPathPage($cPage);
    if (index($cPagePath, $parentPath) == 0 && ($parentPath ne $cPagePath)) {
      push(@result, $cPage);
      $result2 = $result2.",".$cPagePath;
    }
  }
  return \@result;
}

=pod
print Dumper($variable);
=cut

sub getRootPage {
  my %result = ();
  my @pages = getAllPages();
  my $pagesLength = @pages;
  for (my $i = 0; $i < $pagesLength; $i++) {
    my $cPage = $pages[$i];
    my $cPagePath = getPathPage($cPage);
    if ($cPagePath eq "/") {

    for my $hKey ( keys %$cPage ) {
        my $hValue = $cPage->{$hKey};
     	$result{$hKey} = $hValue;
    }
      last;
    }
  }
  return \%result;
}

$stash->set('getAllPages', \&getAllPages);
$stash->set('getPathPage', \&getPathPage);
$stash->set('loadInnerPages', \&loadInnerPages);
$stash->set('getRootPage', \&getRootPage);

#Add new custom functions here
LIBS2_CONTENT





my $templates_index_name = "index.html";
my $templates_index_content = <<'TEMPLATES_INDEX_CONTENT';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
  <title>[% page.title %]</title>
  <meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
</head>

<body>

[% page.content %]

</body>
</html>

TEMPLATES_INDEX_CONTENT

my $proj_file_template_content = <<'PROJ_FILE_TEMPLATE';
# Dapper configuration file
---
name : My Site

Dapper_libs : '_libs'

url: http://vanilladraft.com/
source : _source/
output : _output/
layout : _layout/
links :
    Preface : /preface/
    Feed : http://feeds.feedburner.com/vanilladraft
    Amazon : http://amazon.com/author/markbenson
    Github : http://github.com/markdbenson
    LinkedIn : http://linkedin.com/in/markbenson
    Twitter : https://twitter.com/markbenson
ignore :
    - "^\."
    - "^_"
    - "^design$"
    - "^README.md$"
    - "^Makefile$"
    - "^_libs"

PROJ_FILE_TEMPLATE

=head2 init

Initialize a Dapper project. This method creates a config file, source and template directories.
After calling this method, the project may be built.

=cut

sub init {
    my ($source, $output, $layout, $config) = @_;

    App::Dapper::Utils::create_file($config, $proj_file_template_content);

    App::Dapper::Utils::create_dir($source);
    App::Dapper::Utils::create_file("$source/$source_index_name", $source_index_content);

    App::Dapper::Utils::create_dir($layout);
    App::Dapper::Utils::create_file("$layout/$templates_index_name", $templates_index_content);
    
    App::Dapper::Utils::create_dir('_libs');
    App::Dapper::Utils::create_file("_libs/$libs_name", $libs_content);
    App::Dapper::Utils::create_file("_libs/$libs2_name", $libs2_content);
}

1;
