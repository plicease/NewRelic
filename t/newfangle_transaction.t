use Test2::V0 -no_srand => 1;
use Test2::Tools::AsyncSubtest;
use lib 't/lib';
use LiveTest;
use Time::HiRes qw( usleep );
use NewFangle qw( newrelic_configure_log );
use Carp qw( longmess );

my $app = NewFangle::App->new;

is(
  $app->start_web_transaction("web1"),
  object {
    call [ isa => 'NewFangle::Transaction' ] => T();
    call [ add_attribute_int    => 'foo_int',              10 ] => T();
    call [ add_attribute_long   => 'foo_long',             11 ] => T();
    call [ add_attribute_double => 'foo_double',         3.14 ] => T();
    call [ add_attribute_string => 'foo_string', 'hello perl' ] => T();
    call end => T();
  },
);

is(
  $app->start_non_web_transaction("nonweb1"),
  object {
    call [ isa => 'NewFangle::Transaction' ] => T();
    call [ notice_error => 3, "oh boy this is bad", "Error::Class" ] => U();
  },
);

is(
  $app->start_non_web_transaction("nonweb1"),
  object {
    call [ isa => 'NewFangle::Transaction' ] => T();
    call [ notice_error_with_transaction => 3, "and this has a perl stack trace", "Error::Class", longmess() ] => U();
  },
);

is(
  $app->start_web_transaction('ignore1'),
  object {
    call [ isa => 'NewFangle::Transaction' ] => T();
    call [ record_custom_event => NewFangle::CustomEvent->new("roar") ] => T();
    call [ set_name => 'ignore2' ] => T();
    call [ record_custom_metric => 'cm', 3.14 ] => T();
    call ignore => T();
  },
);

my $outer_txn = $app->start_web_transaction('ignore_pre_fork');
$outer_txn->ignore;

my @children;

foreach my $index (0..25)
{
  usleep int(rand(900))+500;
  push @children, fork_subtest "child $index" => sub {
    srand $$+time;
    usleep int(rand(400));
    my $txn = $app->start_web_transaction("child$index");
    usleep int(rand(500));
    foreach my $index2 (0..3+int(rand(20)))
    {
      my $seg = $txn->start_segment("seg$index2");
      usleep int(rand(6400));
      is $seg->end, T();
    }
    usleep int(rand(500));
    is $txn->end, T();
  };
}

$_->finish for @children;

$outer_txn->end;

done_testing;
