package Starflight::Cache;

use 5.010000;
use strict;
use warnings;

use AnyEvent;

use Starflight::Exceptions;
use Starflight::Cache::Model::Redis;

use Data::Dumper;

our $VERSION = $Starflight::VERSION;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{_logger} = Log::Log4perl::get_logger('Starflight::Cache');
	
	$self->{parent} = $parent;

	$self->{settings} = $parent->{settings}{cache};

	$self->{cache} = {};
	
	if ($self->{settings}{type} =~ /^redis$/i) {
		$self->{model} = Starflight::Cache::Model::Redis->new($self);
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


1;
