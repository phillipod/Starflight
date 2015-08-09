package Starflight::RequestWorker;

use 5.010000;
use strict;
use warnings;

use Coro;
use Coro::Channel::Factory;
use AnyEvent;
use AnyEvent::HTTP;

use Log::Log4perl;

use HTTP::Headers::Util qw(split_header_words);

use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Compress::Bzip2 qw(bzip2 $Bzip2Error);
use IO::Compress::RawDeflate qw(rawdeflate $RawDeflateError);

use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);
use IO::Uncompress::RawInflate qw(rawinflate $RawInflateError);

use Starflight::Exceptions;

use Mojo::DOM;
use Text::Template;

our $VERSION = $Starflight::VERSION;

use Data::Dumper;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{logger} = Log::Log4perl::get_logger('Starflight::RequestWorker');

	$self->{parent} = $parent;
	
	$self->{settings} = $parent->{settings}{request_worker};
	$self->{queue} = $self->channel('Starflight::RequestWorker.worker_queue');

	$self->{config} = $parent->{config};
	
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

sub handler {
	my $self = shift;
	my $workerID = shift;
	my $worker = shift;
	my $work = shift;
	my $item = $work->{item};
	
	if ($item->{method}) {
		http_request $item->{method} => $item->{uri}, headers => $item->{request_headers}, body => $item->{request_body},
			sub {
				my $http_status = delete $_[1]->{Status};
				my $http_reason = delete $_[1]->{Reason};
				my $http_version = delete $_[1]->{HTTPVersion};
				my $http_redirect = delete $_[1]->{Redirect};
				 	
				if (!defined($_[0])) {
					$work->{cv}->send({ http_error => 1, http_status => $http_status, http_reason => $http_reason });
					return;
	 			}
				
				$work->{cv}->send({ http_status => $http_status, http_reason => $http_reason, http_version => $http_version,
						http_redirect => $http_redirect, http_body => $_[0], http_headers => HTTP::Headers->new(%{$_[1]}) });
			};
	}	
}

sub channel {
	my $self = shift;
	my $name = shift;
	
	return $self->{parent}->channel($name);	
}

sub decompress_response {
	my $self = shift;
	my $item = shift;
	my $compressed_data = shift;
	
	my $decompressed_content = undef;

	if (!defined($item->{response_original_content_encoding})) { return; }
	
	if ($item->{response_original_content_encoding} =~ /gzip/i) {
		gunzip \$compressed_data => \$decompressed_content;
	} elsif ($item->{response_original_content_encoding} =~ /bzip2/i) {
		bunzip2 \$compressed_data => \$decompressed_content;
	} elsif ($item->{response_original_content_encoding} =~ /deflate/i) {
		rawinflate \$compressed_data => \$decompressed_content;
	}

	if (defined($decompressed_content)) {
		$item->{response_headers}->remove_header('Content-Encoding');
		$item->{response_headers}->remove_header('Content-Length');
		$item->{response_body} = $decompressed_content;	
	}
}

sub compress_response {
	my $self = shift;
	my $item = shift;
	my $uncompressed_content = shift;

	my $compressed_data = undef;

	if (!defined($item->{request_original_acceptable_encoding})) { return; }
	
	if ($item->{status} != 304) {
	 	my $encoding = undef;
 	
		if ($item->{request_original_acceptable_encoding} =~ /\s*(gzip)(?:\s*,\s*|$)/i) {
			gzip \$uncompressed_content => \$compressed_data, Minimal => 1, Strict => 1;
			$encoding = $1;
		} elsif ($item->{request_original_acceptable_encoding} =~ /\s*(deflate)(?:\s*,\s*|$)/i) {
	   		rawdeflate \$uncompressed_content => \$compressed_data;
			$encoding = $1;
	  	} elsif ($item->{request_original_acceptable_encoding} =~ /\s*(bzip2)(?:\s*,\s*|$)/i) {
	  		bzip2 \$uncompressed_content => \$compressed_data;
			$encoding = $1;
		}
	
		if (defined($compressed_data)) {
			$item->{response_headers}->header('Content-Encoding' => $encoding);
			$item->{response_body} = $compressed_data;
		}
	}
}

sub transform_request_headers {
	my $self = shift;
	my $host_config = shift;
	my $request = shift;
	
	my $headers = $request->headers->clone;
	
	if ($host_config->{server}{host_header}) {
		$headers->header('Host' => $host_config->{server}{host_header});
	}
		
	while (my ($transform_header, $transformation) = each %{$host_config->{headers}{request}{transform}}) {
		Coro::AnyEvent::poll;
#		print "Checking $transform_header\n";
		if ((my $value = $headers->header($transform_header))) {
			$value =~ s/$transformation->{match}/$transformation->{replace}/gi;
			$headers->header($transform_header => $value);
		}
	}

	$headers->remove_header('Accept-Encoding');
	$headers->header('Accept-Encoding' => 'gzip, bzip2, deflate');		
	
	return $headers;
}

sub transform_request {
	my $self = shift;
	my $request_cv = shift;
	my $host_config = shift;
	my $request = shift;
	my $item = shift;
	
	$request_cv->begin();

	$item->{request_headers} = $self->transform_request_headers($host_config, $request);
	$item->{uri} = $request->scheme . '://' . $item->{request_headers}->header('Host') . $request->request_uri;
	$item->{request_body} = $request->raw_body;
	
	$request_cv->end();
}

sub transform_response_headers {
	my $self = shift;
	my $host_config = shift;
	my $item = shift;
	
	if (defined($item->{response_headers}->header('Transfer-Encoding')) && $item->{response_headers}->header('Transfer-Encoding') eq "chunked") {
		$item->{response_headers}->remove_header('Transfer-Encoding');
	}
	
	while (my ($transform_header, $transformation) = each %{$host_config->{headers}{response}{transform}}) {
		Coro::AnyEvent::poll;
#		print "Checking $transform_header\n";
		if ((my $value = $item->{response_headers}->header($transform_header))) {
			$value =~ s/$transformation->{match}/$transformation->{replace}/gi;
			$item->{response_headers}->header($transform_header => $value);
		}
	}
}

sub transform_response {
	my $self = shift;
	my $request_cv = shift;
	my $host_config = shift;
	my $raw_response = shift;
	my $item = shift;

	#print Dumper($raw_response);

	$request_cv->begin();

	$item->{status} = $raw_response->{http_status};
	$item->{response_headers} = HTTP::Headers->new(%{$raw_response->{http_headers}});	
	
	$self->decompress_response($item, $raw_response->{http_body});

	my %mime = ();
    
	if (defined($item->{response_headers}->header('Content-Type'))) {
		my @mime_fields = split(/;/, $item->{response_headers}->header('Content-Type'));
        
		$mime{'Content-Type'} = shift @mime_fields;
        
		foreach my $parameter (shift @mime_fields) {
			my ($name, $value) = split(/=/, $parameter);
			$mime{$name} = $value;
		}
	}

	if ($item->{status} != 304) {
		my $content_type = $mime{'Content-Type'};
        
		if ($host_config->{content}{response}{selection}{$content_type}) {
			my $ops = $host_config->{content}{response}{selection}{$content_type};
			my $dom = Mojo::DOM->new($item->{response_body});
		
			foreach my $type ('add', 'remove', 'replace', 'transform') {
				if (!$ops->{$type}) { next; }

				foreach my $transformation (@{$ops->{$type}}) {
					foreach my $element ($dom->find($transformation->{selector})->each) {
						Coro::AnyEvent::poll;
						if ($transformation->{target} =~ /^attr::(.*?)$/) {
							my $attr = $1;
							my $value = $element->attr($attr);
						
							if ($transformation->{transform} eq "substitute") {
								$value =~ s/$transformation->{match}/$transformation->{replace}/gi;
								$element->attr($attr => $value);
							}						
						} elsif ($transformation->{target} =~ /^child::text$/) {
							my $value = $element->to_string;
						
							if ($transformation->{transform} eq "substitute") {
								$value =~ s/$transformation->{match}/$transformation->{replace}/gi;
								$element->replace($value);
							}						
						} 
					}
				}
			}

			$item->{response_body} = $dom->to_string;	   
		}
	
		$self->{logger}->debug("Checking for text replacements for content type $content_type");
		if ($host_config->{content}{response}{global}{$content_type}) {
			my $ops = $host_config->{content}{response}{global}{$content_type};

			$self->{logger}->trace(Dumper($ops));
			
			foreach my $type ('transform') {
				Coro::AnyEvent::poll;
				if (!$ops->{$type}) { next; }

				foreach my $transformation (@{$ops->{$type}}) {
					$item->{response_body} =~ s/$transformation->{match}/$transformation->{replace}/gi;
				}
			}
		}
	}
	
	if (defined($mime{'charset'}) && $mime{'charset'} =~ /utf8|utf-8/) {
		utf8::encode($item->{response_body});
	}
	
	$self->compress_response($item, $item->{response_body});
	
	$item->{response_headers}->header('Content-Length' => length $item->{response_body});	
	
	$request_cv->end();
}

sub add_response_cookies {
	my $self = shift;
	my $request = shift;
	my $host_config = shift;
	my $item = shift;

	if (!exists $host_config->{cookies}{add}) { return; }
	
	foreach my $cookie (keys %{$host_config->{cookies}{add}}) {
		if (!exists $request->cookies->{$cookie}) {
			if (exists $host_config->{cookies}{add}{$cookie}{trigger}) {
				Coro::AnyEvent::poll;
				$self->{logger}->trace(' - running cookie add trigger for cookie ' . $cookie);
		
				my $run_trigger = $host_config->{cookies}{add}{$cookie}{trigger}->fill_in(PREPEND => 'use JSON; use Data::Dumper;', HASH => { request => \$request });
 
				if (!$run_trigger) { next; } 
			}
			
			if ($host_config->{cookies}{add}{$cookie}{'max-age'}) {
				$host_config->{cookies}{add}{$cookie}{expires} = int(AE::time + $host_config->{cookies}{add}{$cookie}{'max-age'});
			}
			
			$item->{new_cookies}{$cookie} = $host_config->{cookies}{add}{$cookie};
		}
	}
}

sub validate_response {
	my $self = shift;
	my $raw_response = shift;
		
	if ($raw_response->{http_error}) {
		$raw_response->{http_status} == 595 && Starflight::Exception::Proxy::ConnectionError->throw();
		$raw_response->{http_status} == 596 && Starflight::Exception::Proxy::RequestError->throw();
		$raw_response->{http_status} == 597 && Starflight::Exception::Proxy::ResponseError->throw();
	
		Starflight::Exception::Proxy::OtherError->throw();	
	} 
}

sub serve_request {
	my $self = shift;
	my $request_cv = shift;
	my $host_config = shift;
	my $request = shift;
    
}

sub proxy_request {
	my $self = shift;
	my $request_cv = shift;
	my $host_config = shift;
	my $request = shift;
    
	my $item = {
		status => undef, 
		uri => undef,
		method => $request->method,
		request_original_acceptable_encoding => ($request->headers->header('Accept-Encoding') ? "" . $request->headers->header('Accept-Encoding') : undef),
		request_headers => undef,
		request_body => undef,
		response_original_content_encoding => undef,
		response_headers => undef,
		response_body => undef,
	};
		
	$self->transform_request($request_cv, $host_config, $request, $item);

	my $worker_cv = AnyEvent->condvar;
	$self->{queue}->put({ cv => $worker_cv, item => $item });
	my $raw_response = $worker_cv->recv();
	
	$self->validate_response($raw_response);
	
	$item->{response_original_content_encoding} = $raw_response->{http_headers}->header('Content-Encoding');
	
	$self->transform_response($request_cv, $host_config, $raw_response, $item);
	
	$response->status($item->{status});
	$response->headers($item->{response_headers});
	$response->body($item->{response_body});	
}

sub request {
	my $self = shift;
	my $request_cv = shift;
	my $host_config = shift;
	my $request = shift;
	
	my $response = Plack::Response->new();
    
	$request_cv->begin(sub { shift->send($response); });
	
    my $cookies = {};
    
	$self->add_response_cookies($request, $host_config, $cookies);
	$response->cookies($cookies);

	$request_cv->end();    
}	


1;
