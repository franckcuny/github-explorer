package githubexplorer::Gexf;

use Moose;
use XML::Simple;
use IO::All;
use 5.010;

has avg_contrib_by_lang => (is => 'rw', isa => 'HashRef', lazy => 1, default => sub {{}});
has schema => ( is => 'ro', isa => 'Object', required => 1 );
has id_edges => (
    is      => 'rw',
    isa     => 'Num',
    traits  => ['Counter'],
    default => 0,
    handles => { inc_edges => 'inc' }
);

has graph => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub {
        my $graph = {
            gexf => {
                version => "1.1",
                meta    => { creator => ['linkfluence'] },
                graph   => {
                    type       => 'static',
                    attributes => [
                        {
                            class     => 'edge',
                            type      => 'static',
                            attribute => [
                                {
                                    id    => 0,
                                    type  => 'string',
                                    title => 'language'
                                },
                                {
                                    id    => 0,
                                    type  => 'float',
                                    title => 'collaborate'
                                },
                            ]
                        },
                        {
                            class     => 'node',
                            type      => 'static',
                            attribute => [
                                {
                                    id    => 0,
                                    type  => 'string',
                                    title => 'name'
                                },
                                {
                                    id    => 1,
                                    type  => 'string',
                                    title => 'type',
                                },
                                {
                                    id    => 2,
                                    type  => 'float',
                                    title => 'followers_count'
                                },
                                {
                                    id    => 3,
                                    type  => 'float',
                                    title => 'following_count'
                                },
                                {
                                    id    => 4,
                                    type  => 'float',
                                    title => 'forks',
                                },
                                {
                                    id    => 5,
                                    type  => 'string',
                                    title => 'location',
                                },
                                {
                                    id    => 6,
                                    type  => 'float',
                                    title => 'public_gist_count',
                                },
                                {
                                    id    => 7,
                                    type  => 'float',
                                    title => 'public_repo_count',
                                },
                                {
                                    id    => 8,
                                    type  => 'string',
                                    title => 'language',
                                },
                                {
                                    id    => 9,
                                    type  => 'string',
                                    title => 'description',
                                },
                                {
                                    id    => 10,
                                    type  => 'float',
                                    title => 'watchers',
                                }
                            ]
                        },
                    ]
                }
            }
        };
    }
);

sub gen_gexf {
    my $self = shift;

    #$self->_average_by_langage();

    $self->basic_profiles;
    my $basic_profiles = $self->dump_gexf;
    $basic_profiles > io('basic_profiles.gexf');

    #$self->profiles_from_repositories;
    #my $profiles_from_repositories = $self->dump_gexf;
    #$profiles_from_repositories > io('profiles_from_repositories.gexf');

    #$self->repositories_from_profiles;
    #my $repositories_from_profiles = $self->dump_gexf;
    #$repositories_from_profiles > io('repositories_from_profiles.gexf');
}

sub dump_gexf {
    my $self = shift;
    my $xml_out = XMLout( $self->graph, AttrIndent => 1, keepRoot => 1 );
    say "total nodes => ".scalar @{$self->graph->{gexf}->{graph}->{nodes}->{node}};
    say "total edges => ".scalar @{$self->graph->{gexf}->{graph}->{edges}->{edge}};
    $self->graph->{gexf}->{graph}->{nodes} = undef;
    $self->graph->{gexf}->{graph}->{edges} = undef;
    return $xml_out;
}

sub basic_profiles {
    my $self = shift;
    $self->id_edges(0);
    say "start basic_profiles ...";
    my $profiles =
    $self->schema->resultset('Profiles')->search();

    while ( my $profile = $profiles->next ) {
        my $node = $self->_get_node_for_profile($profile);
        push @{ $self->graph->{gexf}->{graph}->{nodes}->{node} }, $node;
    }

    my $edges = $self->schema->resultset('Follow')->search();
    my $id    = 0;
    while ( my $edge = $edges->next ) {
        my $collaborate = 1;
#        my $forks_source = $self->schema->resultset('Fork')->search({profile =>
#                $edge->origin->id});
#        while (my $fork = $forks_source->next) {
#            my $contrib = $self->schema->resultset('Fork')->search({repos =>
#                    $fork->repos->id});
#            while (my $c = $contrib->next) {
#                $collaborate++ if ($c->profile->id == $edge->dest->id);
#            }
#        }
        my $e = {
            source => $edge->origin->id,
            target => $edge->dest->id,
            id     => $self->inc_edges,
            weight => $collaborate,
            collaborate => $collaborate,
            language => $edge->origin->main_language,
        };
        push @{ $self->graph->{gexf}->{graph}->{edges}->{edge} }, $e;
    }
    say "basic_profiles done";
}

sub profiles_from_repositories {
    my $self = shift;
    $self->id_edges(0);
    say "start profiles_from_repositories ...";

    my ($nodes);
    my $profiles = $self->schema->resultset('Profiles')->search();
    while ( my $profile = $profiles->next ) {
        my $node = $self->_get_node_for_profile($profile);
        push @{ $self->graph->{gexf}->{graph}->{nodes}->{node} }, $node;
    }
    my $edges;
    my $repositories = $self->schema->resultset('Repositories')->search();
    while ( my $repos = $repositories->next ) {
        my $forks = $self->schema->resultset('Fork')
            ->search( { repos => $repos->id } );
        if ($repos->main_language && exists
            $self->avg_contrib_by_lang->{$repos->main_language}->{avg} &&
            $forks < $self->avg_contrib_by_lang->{$repos->main_language}->{avg}){
            next;
        }
        my @profiles;
        while ( my $fork = $forks->next ) {
            push @profiles, $fork->profile->id;
        }
        foreach my $p (@profiles) {
            foreach my $t (@profiles) {
                next if $t eq $p;
                if (exists $edges->{$p}->{$t}) {
                    $edges->{$p}->{$t}->{weight}++;
                }elsif(exists $edges->{$t}->{$p}) {
                    $edges->{$t}->{$p}->{weight}++;
                }else{
                    $edges->{$p}->{$t}->{weight}++;
                }
            }
        }
    }
    foreach my $e (keys %$edges) {
        foreach my $t (keys %{$edges->{$e}}) {
            next unless $edges->{$e}->{$t}->{weight} > 5;
            my $edge = {
                id     => $self->inc_edges,
                source => $e,
                target => $t,
                weight => $edges->{$e}->{$t}->{weight},
            };
            push @{ $self->graph->{gexf}->{graph}->{edges}->{edge} }, $edge;
        }
    }
    say "profiles_from_repositories done";
}

sub repositories_from_profiles {
    my $self = shift;
    $self->id_edges(0);
    say "start repositories_from_profiles ...";

    my ($nodes);
    my $repositories = $self->schema->resultset('Repositories')->search();
    while ( my $repos = $repositories->next ) {
        next if $repos->name =~ /dotfiles/;

        if ( !exists $nodes->{ $repos->name } ) {
            $nodes->{ $repos->name } = {
                id        => $repos->name,
                label     => $repos->name,
                attvalues => {
                    attvalue => [
                        { for => 0,  value => $repos->name },
                        { for => 1,  value => "repository" },
                        { for => 4,  value => $repos->forks },
                        { for => 9,  value => $repos->description },
                        { for => 10, value => $repos->watchers },
                        { for => 8,  value => $repos->main_language },
                    ],
                },
            };
        }
    }
    map {
        push @{ $self->graph->{gexf}->{graph}->{nodes}->{node} },
            $nodes->{$_}
    } keys %$nodes;

    my $edges;
    my $profiles = $self->schema->resultset('Profiles');
    while ( my $profile = $profiles->next ) {
        my $forks = $self->schema->resultset('Fork')->search({profile =>
                $profile->id});
        my @repos;
        while (my $fork = $forks->next) {
            push @repos, $fork->repos->name;
        }
        foreach my $r (@repos) {
            foreach my $t (@repos) {
                next if $t eq $r;
                if (exists $edges->{$r}->{$t}) {
                    $edges->{$r}->{$t}->{weight}++;
                }elsif(exists $edges->{$t}->{$r}){
                    $edges->{$t}->{$r}->{weight}++;
                }else{
                    $edges->{$r}->{$t}->{weight}++;
                }
            }
        }
    }
    foreach my $e (keys %$edges) {
        foreach my $t (keys %{$edges->{$e}}) {
            next if $edges->{$e}->{$t}->{weight} < 5;
            my $edge = {
                id     => $self->inc_edges,
                source => $e,
                target => $t,
                weight => $edges->{$e}->{$t}->{weight},
            };
            push @{ $self->graph->{gexf}->{graph}->{edges}->{edge} }, $edge;
        }
    }
    say "repositories_from_profiles done";
}

sub _get_node_for_profile {
    my ( $self, $profile ) = @_;
    my $node      = {
        id        => $profile->id,
        label     => $profile->login,
        attvalues => {
            attvalue => [
                { for => 0, value => $profile->name },
                { for => 1, value => "profile" },
                { for => 2, value => $profile->followers_count },
                { for => 3, value => $profile->following_count },
                { for => 5, value => $profile->country },
                { for => 6, value => $profile->public_gist_count },
                { for => 7, value => $profile->public_repo_count },
                { for => 8, value => $profile->main_language },
            ]
        },
    };
    return $node;
}

#sub _get_languages_for_profile {
#    my ( $self, $profile ) = @_;
#
#    my $forks = $self->schema->resultset('Fork')
#        ->search( { profile => $profile->id } );
#
#    my %languages;
#    while ( my $fork = $forks->next ) {
#        my $languages = $self->schema->resultset('RepoLang')
#            ->search( { repository => $fork->repos->id } );
#        while ( my $lang = $languages->next ) {
#            $languages{ $lang->language->name } += $lang->size;
#        }
#    }
#    my @sorted_lang
#        = sort { $languages{$b} <=> $languages{$a} } keys %languages;
#    return ( \%languages, \@sorted_lang );
#}

sub _average_by_langage {
    my $self = shift;
    my $hash_lang;
    my $repositories = $self->schema->resultset('Repositories')->search();
    say "gather stats ...";
    while ( my $repos = $repositories->next ) {
        next unless $repos->main_language;
        $hash_lang->{ $repos->main_language }->{repositories}++;
        my $forks = $self->schema->resultset('Fork')->search( { repos => $repos->id } )->count;
        $hash_lang->{ $repos->main_language }->{contributors} += $forks;
        $hash_lang->{$repos->main_language}->{avg} = int ($hash_lang->{$repos->main_language}->{contributors} / $hash_lang->{$repos->main_language}->{repositories});
    };
    $self->avg_contrib_by_lang($hash_lang);
}

1;
