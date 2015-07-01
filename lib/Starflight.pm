=head1 NAME

Starflight - Coro-based content-altering reverse proxy

=head1 DESCRIPTION

Starflight is a Coro-based HTTP reverse proxy. Its intended application is for content delivery networks
aggregating backend assets.

It supports alteration of the content returned according to user-defined rules, and additionally
supports calling user-defined web services when specific requests are received.

Due to the single-threaded nature of Coro, multiple instances are required in order to support multiple core
operation. However, extensive use of Coro microthreads and asynchronous within each process allows each
instance to handle multiple connections. Additionally, horizontal distribution allows Starflight to scale
past single machine deployments.

Starflight achieves synchronisation between multiple cores and multiple systems by allowing other systems
to provide configuration storage. Currently a Redis backend is implemented, however the configuration model
allows any style of backend to be added with relative ease - such as calling a web service to provide 
configuration.

The utilisation of Redis allows multiple instances of Starflight to simultaneously see configuration updates
in near realtime.

=cut

package Starflight;

use 5.010000;
use strict;
use warnings;

use Data::Dumper;

use EV;
use Coro;
use Coro::AnyEvent;
use Coro::EV;
use Coro::Channel::Factory;
use AnyEvent;
use AnyEvent::DNS::Cache::Simple;

use Log::Log4perl;

use Starflight::Exceptions;
use Starflight::Config;
use Starflight::Cache;
use Starflight::RequestWorker;
use Starflight::TriggerWorker;
use Starflight::Engine;

use Plack::Runner;

our $VERSION = '0.01';

sub new {
	my $class = shift;
	my $args = shift;
	
	my $self = {};

	bless($self, $class);

	Log::Log4perl::init_and_watch($args->{'logging'}{'config_file'}, $args->{'logging'}{'reload_interval'});
	
	$self->{logger} = Log::Log4perl::get_logger('Starflight');
	
	$self->{settings}{config} = $args->{'config'};
	$self->{settings}{cache} = $args->{'cache'};
	$self->{settings}{server} = $args->{'server'};
	$self->{settings}{request_worker} = $args->{'request_worker'};
	$self->{settings}{trigger_worker} = $args->{'trigger_worker'};

	$self->{_channel_factory} = Coro::Channel::Factory->new();

	$self->{started} = 0;
	
	$self->{config} = Starflight::Config->new($self);
	$self->{cache} = Starflight::Cache->new($self);
	$self->{request_worker} = Starflight::RequestWorker->new($self);	
	$self->{trigger_worker} = Starflight::TriggerWorker->new($self);	
	$self->{engine} = Starflight::Engine->new($self);
		
	return $self;
}

sub start {
	my $self = shift;
		
	my @plack_parameters = ();

	# Build Plack options
	push(@plack_parameters, '-s', 'Corona');
	push(@plack_parameters, '-p', $self->{settings}{server}{'listen_port'});
	push(@plack_parameters, '-o', $self->{settings}{server}{'listen_address'});
	push(@plack_parameters, '-E', 'deployment');
	
	# Build Plack
	my $runner = Plack::Runner->new();
	$runner->parse_options(@plack_parameters);

	# Setup DNS cache
	$self->{resolver} = AnyEvent::DNS::Cache::Simple->register(
	        ttl => 60,
	        negative_ttl => 5,
	        timeout => [1,1]
        );
        
	# Start... first services, then the workers
   	$self->{config}->start();
	$self->{cache}->start();
	$self->{trigger_worker}->start();
	$self->{request_worker}->start();
	$self->{engine}->start();
	$self->{logger}->info('Started');
	$self->{state} = 'started';
	
	# Watch number of workers running to determine when to exit main process
	async {
		while($self->{state} ne 'stopped') {
			if ($self->{state} eq 'stopping') {
				if ($self->{request_worker}->{workers} || $self->{trigger_worker}->{workers}) { 
					$self->{logger}->trace('stopping - waiting on ' . $self->{request_worker}->{workers} . ' request workers and ' . $self->{trigger_worker}->{workers} . ' trigger workers');
				} else {
					$self->{state} = 'stopped';   
				}
			} 
			Coro::AnyEvent::sleep 1;
		}
		$self->{logger}->info('Stopped');
		exit;	 
	};

	# And now start the web application
	$runner->run(sub { $self->{engine}->run(@_); });
}

sub channel {
	my $self = shift;
	my $name = shift;
	
	return $self->{_channel_factory}->name($name);	
}

sub stop {
	my $self = shift;

	if ($self->{state} ne 'started') {
		$self->{logger}->warn("can't stop - state is '" . $self->{state} . "' instead of 'started'");
		return;	
	}
	
	$self->{logger}->info("Stopping");
	$self->{state} = 'stopping';
	
	$self->{engine}->stop();
	$self->{request_worker}->stop();	
   	$self->{trigger_worker}->stop();
   	$self->{resolver} = undef;
   	
};

1;
