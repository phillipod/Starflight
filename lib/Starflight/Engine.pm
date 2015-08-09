package Starflight::Engine;

use 5.010000;
use strict;
use warnings;

use Plack::Request;
use Plack::Response;

use AnyEvent;
use Coro;
use Data::Dumper;
use HTTP::Date;
use Scalar::Util qw( blessed );

use Try::Tiny;
use Starflight::Exceptions;

our $VERSION = $Starflight::VERSION;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{logger} = Log::Log4perl::get_logger('Starflight::Engine');

	$self->{parent} = $parent;
	$self->{config} = $parent->{config};
	$self->{request_worker} = $parent->{request_worker};
	$self->{trigger_worker} = $parent->{trigger_worker};
	
	return $self;
}

sub start {
	my $self = shift;
	
	$self->{state} = 'started';	
}

sub stop {
	my $self = shift;
		
	$self->{state} = 'stopped';	
}

sub run {
	my $self = shift;
	
	my ($response) = $self->handler(@_);

	return $response->finalize;
}

sub request_validation {
	my $self = shift;
	my $req = shift;
		
	if ($req->protocol ne 'HTTP/1.0' && $req->protocol ne 'HTTP/1.1') {
		Starflight::Exception::Protocol::Version::Unsupported->throw(
				http_version_supplied => $req->protocol, 
				http_version_expected => 'HTTP/1.0 or HTTP/1.1');
	}
	
	if (!defined($req->header('Host'))) {
		Starflight::Exception::Headers::Host::Absent->throw();
	}

	if (!$self->{config}->host_exists({ -name => $req->header('Host')})) {
		Starflight::Exception::Headers::Host::Unknown->throw(
				http_redirect_location => '//google.co.nz');
	}
}

sub handler {
	my $self = shift;
	my $env = shift;
	
	my $request = Plack::Request->new($env);
	my $response = undef;
	my $host_config = undef; 
	
    $self->{logger}->trace("Dumping environment: " . Dumper($env));
	try {
		if ($self->{state} ne 'started') {
			Starflight::Exception::Proxy::ConnectionError->throw();	
		}
		
		$self->request_validation($request);
		$self->{config}->host_config({ -name => $request->header('Host') }, \$host_config);
		
		my $cv = AnyEvent->condvar;
		$self->{request_worker}->request($cv, $host_config, $request);
		
		$response = $cv->recv();
		
	} catch {
		die $_ unless blessed $_ && $_->can('rethrow');
				
		if ($_->isa('Starflight::Exception::HTTP')) {
			$response = Plack::Response->new($_->http_status_code, undef, "\n<br/>\n$_\n<br/>\n"); # . $_->trace->as_string)
		} else {
			$response = Plack::Response->new(500, undef, "<h1>Internal Server Error!</h1>\n<br/>\n<br/>");	
		}
		
		$response->header('Content-Type' => 'text/html');
		
	} finally {
		$response->header('Date' => time2str(AE::time));
	};
	
	$self->{trigger_worker}->trigger($host_config, $request, $response, AE::time);
	
	return $response;
}

1;
