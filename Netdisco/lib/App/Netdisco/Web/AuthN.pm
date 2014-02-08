package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

hook 'before' => sub {
    params->{return_url} ||= uri_for('/inventory');

    if (! session('logged_in_user') && request->path ne uri_for('/login')->path) {
        if (setting('trust_x_remote_user') and scalar request->header('X-REMOTE_USER')) {
            session(logged_in_user => scalar request->header('X-REMOTE_USER'));
            session(logged_in_user_realm => 'users');
        }
        elsif (setting('trust_remote_user') and $ENV{REMOTE_USER}) {
            session(logged_in_user => $ENV{REMOTE_USER});
            session(logged_in_user_realm => 'users');
        }
        elsif (setting('no_auth')) {
            session(logged_in_user => 'guest');
            session(logged_in_user_realm => 'users');
        }
        else {
            # user has no AuthN - force to handler for '/'
            request->path_info('/');
        }
    }
};

get qr{^/(?:login(?:/denied)?)?} => sub {
    template 'index';
};

# override default login_handler so we can log access in the database
post '/login' => sub {
    my ($success, $realm) = authenticate_user(
        params->{username}, params->{password}
    );

    if ($success) {
        session logged_in_user => params->{username};
        session logged_in_user_realm => $realm;

        schema('netdisco')->resultset('UserLog')->create({
          username => session('logged_in_user'),
          userip => request->remote_address,
          event => "Login",
          details => params->{return_url},
        });

        redirect params->{return_url} || uri_for('/');
    }
    else {
        schema('netdisco')->resultset('UserLog')->create({
          username => params->{username},
          userip => request->remote_address,
          event => "Login Failure",
          details => params->{return_url},
        });

        vars->{login_failed}++;
        forward uri_for('/login'), { login_failed => 1 }, { method => 'GET' };
    }
};

# we override the default login_handler, so logout has to be handled as well
any ['get','post'] => '/logout' => sub {

    schema('netdisco')->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip => request->remote_address,
      event => "Logout",
      details => '',
    });

    session->destroy;
    if (params->{return_url}) {
        redirect params->{return_url};
    }
    else {
        return "OK, logged out successfully.";
    }
};

true;
