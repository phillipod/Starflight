package Starflight::TriggerWorker;

use 5.010000;
use strict;
use warnings;

use Coro;
use Coro::Channel::Factory;
use AnyEvent;
use AnyEvent::HTTP;
use Log::Log4perl;

use Text::Template;
use POSIX::strftime::Compiler;

use Starflight::Exceptions;

our $VERSION = $Starflight::VERSION;

use Data::Dumper;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{logger} = Log::Log4perl::get_logger('Starflight::TriggerWorker');

	$self->{parent} = $parent;
	
	$self->{settings} = $parent->{settings}{trigger_worker};
	$self->{queue} = $self->channel('Starflight::TriggerWorker.worker_queue');
 
	$self->{config} = $parent->{config};

	$self->{timestamp_formatter} = POSIX::strftime::Compiler->new('%Y-%m-%dT%H:%M:%S%z');
	
	return $self;
}

sub start {
	my $self = shift;
	
	my $workersOverride = shift;

	my $workers = (defined($workersOverride) ? $workersOverride : $self->{settings}{workers});
	
	for (my $i = 0; $i < $workers; $i++) {
		$self->worker($i);
		$self->{workers}++;
	}
}

sub stop {
	my $self = shift;
	
	$self->{queue}->shutdown();   
}

sub worker {
	my $self = shift;
	my $workerID = shift;
	my $workerString = "worker\[$workerID\]";

	my $worker = async {
		while(my $work = $self->{queue}->get()) {
			$self->{logger}->trace($workerString . ' - Work item received');
			
			$self->handler($workerID, $workerString, $work);
			cede;
		}

		$self->{logger}->trace($workerString . ' - terminating');
		$self->{workers}--;
	};
	
	push(@{$self->{_workers}}, $worker);
}

use JSON;

sub handler {
	my $self = shift;
	my $workerID = shift;
	my $worker = shift;
	my $work = shift;
		
	my $host_config = $work->{host_config};
	my $request = $work->{request};
	my $response = $work->{response};
	
	foreach my $trigger (keys %{$host_config->{triggers}}) {
		my $trigger_config = $self->{config}->trigger_config($host_config->{triggers}{$trigger});
		
		$self->{logger}->trace($worker . ' - running trigger ' . $trigger);
		
		my $run_trigger = $trigger_config->{trigger}->fill_in(HASH => { request => \$request });
 
		if (!$run_trigger) { next; }
		
		my $timestamp = $self->{timestamp_formatter}->to_string(localtime($work->{timestamp}));
		my $action_data = $trigger_config->{action}{template}->fill_in(PREPEND => 'use JSON;', HASH => { request => \$request, server => \$host_config->{server}, remote_address => (exists $request->{env}->{'HTTP_X_FORWARDED_FOR'} ? $request->{env}->{'HTTP_X_FORWARDED_FOR'} : $request->address()), timestamp => \$timestamp, 'time' => \$work->{timestamp} });

		$self->{logger}->debug("$trigger: action request body: $action_data");	   
		my $cv = AnyEvent->condvar();
		
		http_request $trigger_config->{action}{method} => $trigger_config->{action}{destination}, timeout => 5, headers => $trigger_config->{action}{headers}, body => $action_data,
			sub {
				my $http_status = delete $_[1]->{Status};
				my $http_reason = delete $_[1]->{Reason};
				my $http_version = delete $_[1]->{HTTPVersion};
				my $http_redirect = delete $_[1]->{Redirect};
				 	
				if (!defined($_[0])) {
					$self->{logger}->error($worker . " - trigger request error: " . Dumper({ http_error => 1, http_status => $http_status, http_reason => $http_reason }));
	 			}
				
				$cv->send();
			};
		$cv->recv();
	}
}

sub channel {
	my $self = shift;
	my $name = shift;
	
	return $self->{parent}->channel($name);	
}

sub trigger {
	my $self = shift;
	my $host_config = shift;
	my $request = shift;
	my $response = shift;
	my $timestamp = shift;
	
	$self->{queue}->put({ host_config => $host_config, request => $request, response => $response, timestamp => $timestamp });
}

1;
