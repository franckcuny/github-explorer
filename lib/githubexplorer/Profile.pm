package githubexplorer::Profile;
use 5.010;
use Moose::Role;
use Net::GitHub::V2::Users;

has banned_profiles =>
    ( isa => 'ArrayRef', is => 'ro', default => sub { [qw/gitpan/] } );

sub fetch_profile {
    my ( $self, $login, $depth ) = @_;

    return if grep { $_ =~ /$login/i } @{ $self->banned_profiles };

    my $profile = $self->_profile_exists($login);

    my $github = Net::GitHub::V2::Users->new(
        owner => $login,
        login => $self->api_login,
        token => $self->api_token,
    );

    if ( !$profile ) {
        return if $depth > 3;
        say "fetch profile for $login ($depth)...";
        sleep(1);
        my $desc = $github->show;
        if (!$desc || ($desc && exists $desc->{error})) {
            sleep(60);
            $self->fetch_profile($login, $depth);
        }
        $profile = $self->_create_profile( $login, $github->show, $depth );
        sleep(2);
        if ( $self->with_repo ) {
            $self->fetch_repositories( $profile, $github->list );
        }
    }

   if ( !$profile->done ) {
       my $local_depth = $depth + 1;
       my $followers = $github->followers();
       sleep(1);
       my $following = $github->following();

       # foreach my $f (@$followers) {
           # say $to->login . " is followed by " . $from;
       #     $self->_create_relation($f, $profile, $local_depth);
       # }
       foreach my $f (@$following) {
           # say $profile->login . " follow " . $f;
           $self->_create_relation($profile, $f, $local_depth);
       }
       say "update profile for $login: done";
       $profile->update( { done => 1 } );
   }

   sleep(1);
   $profile;
}

sub _create_relation {
    my ( $self, $from, $to, $depth ) = @_;

    say "-> create a relation from ".$from->login." to $to";
    if ( my $p = $self->_profile_exists($to) ) {
        if ( !$self->_relation_exists( $from->id, $p->id ) ) {
            $self->schema->txn_do(
                sub {
                    $self->schema->resultset('Follow')->find_or_create(
                        {
                            origin => $from->id,
                            dest   => $p->id,
                        }
                    );
                }
            );
        }
        return;
    }
    my $p = $self->fetch_profile( $to, $depth );
    return unless $p;
    $self->schema->txn_do(
        sub {
            $self->schema->resultset('Follow')->find_or_create(
                {
                    origin => $from->id,
                    dest   => $p->id,
                }
            );
        }
    );
}

sub _relation_exists {
    my ( $self, $from, $to ) = @_;
    $self->schema->resultset('Follow')
        ->find( { origin => $from, dest => $to } );
}

sub _profile_exists {
    my ( $self, $login ) = @_;
    my $profile
        = $self->schema->resultset('Profiles')->find( { login => $login } );
    return $profile;
}

sub _create_profile {
    my ( $self, $user_name, $profile, $depth ) = @_;

    $profile->{depth} = $depth;

    my $profile_rs;

    $self->schema->txn_do(
        sub {
            $profile_rs
                = $self->schema->resultset('Profiles')->create($profile);
        }
    );
    say '-> '.$profile_rs->login . "'s profile created";
    return $profile_rs;
}

1;
