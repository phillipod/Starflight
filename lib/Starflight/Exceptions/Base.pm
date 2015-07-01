package Starflight::Exceptions::Base;

use 5.010000;
use strict;
use warnings;

use base 'Exception::Class::Base';

$Starflight::Exceptions::Base::VERSION = $Starflight::VERSION;

sub new {
	my $proto = shift;
	my $class = ref $proto || $proto;

	my $self = bless { $class->_defaults }, $class;

	$self->_initialize(@_);

	return $self;
}

sub _defaults { return }

1;
