package Starflight::Model::Redis;

use 5.010000;
use strict;
use warnings;

use Coro;
use Coro::Channel::Factory;
use AnyEvent;
use AnyEvent::Hiredis;

use Starflight::Exceptions;

our $VERSION = $Starflight::VERSION;

use Data::Dumper;

sub channel {
	my $self = shift;
	my $name = shift;
	
	return $self->{parent}->channel($name);	
}

sub start {
	my $self = shift;
	my $workersOverride = shift;

	my $workers = (defined($workersOverride) ? $workersOverride : $self->{settings}{workers});
	
	$self->{logger}->info("redis workers: $workers");
	
	for (my $i = 0; $i < $workers; $i++) {
		$self->worker($i);
	}
}

sub worker {
	my $self = shift;
	my $workerID = shift;
	my $workerString = ref($self) . "\[$workerID\]";

	my $worker = async {
		my $redis = AnyEvent::Hiredis->new(host => $self->{settings}{host}, port => $self->{settings}{port});
		
		while(my $work = $self->{queue}->get()) {
			$self->handler($workerID, $workerString, $redis, $work);
			cede;
		}
	};
	
	push(@{$self->{_workers}}, $worker);
}

sub handler {
	my $self = shift;
	my $workerID = shift;
	my $worker = shift;
	my $redis = shift;
	my $work = shift;
	
#	print "$worker: entering handler > " . Dumper($work);
	
	if ($work->{command}) {
		$redis->command( $work->{command}, sub {
			$work->{cv}->send({ result => $_[0], error => $_[1] });
		});
	}
}

sub command {
	my $self = shift;
	my $command = shift;
	
	my $cv = AnyEvent->condvar;
	
	$self->{queue}->put({ cv => $cv, command => $command});
	
	my $res = $cv->recv();
		
	if ($res->{error}) {
		Starflight::Exception::Redis::Error->throw(message => $res->{error});
	} elsif (!defined($res->{result})) {
		Starflight::Exception::Redis::NoResult->throw();
	}
	
	return $res->{result};
}

1;
