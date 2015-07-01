package Starflight::Config;

use 5.010000;
use strict;
use warnings;

use AnyEvent;

use Coro;
use Starflight::Exceptions;
use Starflight::Config::Model::Redis;

use Data::Dumper;

our $VERSION = $Starflight::VERSION;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{parent} = $parent;

	$self->{settings} = $parent->{settings}{config};

	$self->{cache} = {};
	$self->{locks} = new Coro::SemaphoreSet 1;
	
	if ($self->{settings}{type} =~ /^redis$/i) {
		$self->{model} = Starflight::Config::Model::Redis->new($self);
	}
	
	return $self;
}

sub start {
	my $self = shift;
	
	$self->{model}->start();
}

sub channel {
	my $self = shift;
	my $name = shift;
	
	return $self->{parent}->channel($name);	
}

sub host_exists {
	my $self = shift;
	
	return ($self->{model}->get_host_serial(@_) >= 1 ? 1 : 0);	
}

sub trigger_exists {
	my $self = shift;
	
	return ($self->{model}->get_trigger_serial(@_) >= 1 ? 1 : 0);	
}

sub host_config {
	my $self = shift;
	my $host_selector = shift;
	my $host_config = shift;
	my $host_key = undef;
	
	if ($host_selector->{-key}) {
		$host_key = $host_selector->{-key};
	} else {
		$host_key = "config://$host_selector->{-name}/";
	}

	if (!defined($self->{cache}{$host_key}{server}{sn}) 
			|| (defined($self->{cache_expiry}{$host_key}) && AE::time >= $self->{cache_expiry}{$host_key})
			|| ($self->{cache}{$host_key}{server}{sn} < $self->{model}->get_host_serial({ -key => $host_key . "server/" }))) {
		if ($self->{locks}->try($host_key)) {
		  $self->{model}->load_host_config({ -key => $host_key }, $self->{cache}{$host_key});
				
		  my $reload_interval = ($self->{cache}{$host_key}{server}{reload_interval} ? $self->{cache}{$host_key}{server}{reload_interval} : 30);
		  $self->{cache_expiry}{$host_key} = (AE::time + $reload_interval);
		  
		  $self->{locks}->up($host_key);
		} else {
			$self->{locks}->wait($host_key);
		}
		#print "Set expiry: " . $self->{cache_expiry}{$host_key} . "\n";
		#print "Now: " . AE::time . "\n";
#	} else {
#		print "Using cached redis config...\n";	
	}
	
	${$host_config} = \%{$self->{cache}{$host_key}};
	
	#print Dumper(${$host_config});
	
	#return $self->{cache}{$host_key};
}

sub trigger_config {
	my $self = shift;
	my $trigger_key = shift;
	my $trigger_config = shift;
	
	#print "Dumping cache: " . Dumper($self->{cache}) . Dumper($self->{cache_expiry});
	if (!defined($self->{cache}{$trigger_key}) 
			|| (defined($self->{cache_expiry}{$trigger_key}) && AE::time >= $self->{cache_expiry}{$trigger_key})
			|| ($self->{cache}{$trigger_key}{sn} < $self->{model}->get_trigger_serial($trigger_key))) {
#		print "Updating cache from redis..\n";
		#$self->{cache}{$trigger_key} = { };

		if ($self->{locks}->try($trigger_key)) {
			$self->{model}->load_trigger_definition($trigger_key, \$self->{cache}{$trigger_key});
				
			my $reload_interval = ($self->{cache}{$trigger_key}{reload_interval} ? $self->{cache}{$trigger_key}{reload_interval} : 30);
			$self->{cache_expiry}{$trigger_key} = (AE::time + $reload_interval);	
			$self->{locks}->up($trigger_key);
		} else {
			$self->{locks}->wait($trigger_key);
		}
		
		#print "Set expiry: " . $self->{cache_expiry}{$trigger_key} . "\n";
		#print "Now: " . AE::time . "\n";
#	} else {
#		print "Using cached redis config...\n";	
	}
	
	${$trigger_config} = \%{$self->{cache}{$trigger_key}};
	#return $self->{cache}{$trigger_key};
}
1;
