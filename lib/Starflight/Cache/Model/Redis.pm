package Starflight::Cache::Model::Redis;

use 5.010000;
use strict;
use warnings;

use base 'Starflight::Model::Redis';

use Coro;
use AnyEvent;

use Starflight::Exceptions;

our $VERSION = $Starflight::VERSION;

use Data::Dumper;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{logger} = Log::Log4perl::get_logger('Starflight::Cache::Model::Redis');
	
	$self->{parent} = $parent;
	$self->{settings} = $parent->{settings}{redis};
	
	$self->{queue} = $self->channel('Starflight::Cache::Model::Redis.worker_queue');
		
	return $self;
}


1;
