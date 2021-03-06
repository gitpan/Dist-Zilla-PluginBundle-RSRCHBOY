#
# This file is part of Dist-Zilla-PluginBundle-RSRCHBOY
#
# This software is Copyright (c) 2013 by Chris Weyl.
#
# This is free software, licensed under:
#
#   The GNU Lesser General Public License, Version 2.1, February 1999
#
package Dist::Zilla::PluginBundle::RSRCHBOY;
our $AUTHORITY = 'cpan:RSRCHBOY';
# git description: 0.054-1-g77bdb49
$Dist::Zilla::PluginBundle::RSRCHBOY::VERSION = '0.055';

# ABSTRACT: Zilla your distributions like RSRCHBOY!

use utf8;
use v5.10;

use Moose;
use namespace::autoclean;
use MooseX::AttributeShortcuts;
use Moose::Util::TypeConstraints;

use autodie 0.20;
use autobox::Core;

use Dist::Zilla;
with
    'Dist::Zilla::Role::PluginBundle::Easy',
    'Dist::Zilla::Role::PluginBundle::PluginRemover' => { -version => '0.102' },
    'Dist::Zilla::Role::PluginBundle::Config::Slicer',
    'Dist::Zilla::PluginBundle::RSRCHBOY::Role::Git',
    ;

use Config::MVP::Slicer 0.302;
use Path::Class;

has github_user => (is => 'lazy', isa => 'Str', builder => sub { 'RsrchBoy' });
has set_github_user => (is => 'lazy', isa => 'Str', builder => sub { 1 });

# FIXME this next section is kinda... ugly

has is_app     => (is => 'lazy', isa => 'Bool');
has is_private => (is => 'lazy', isa => 'Bool');
has rapid_dev  => (is => 'lazy', isa => 'Bool');

sub _build_is_app     { $_[0]->payload->{cat_app} || $_[0]->payload->{app} }
sub _build_is_private { $_[0]->payload->{private}                          }
sub _build_rapid_dev  { $_[0]->payload->{rapid_dev}                        }

my $_d = sub { my $key = shift; sub { shift->payload->{$key} } };
has $_ => (is => 'lazy', isa => 'Bool')
    for qw{ sign tweet github install_on_release };
has "is_$_" => (is => 'lazy', isa => 'Bool', builder => $_d->($_))
    for qw{ task };

sub _build_sign               { shift->payload->{sign}               // 1 }
sub _build_tweet              { shift->payload->{tweet}              // 1 }
sub _build_github             { shift->payload->{github}             // 1 }
sub _build_install_on_release { shift->payload->{install_on_release} // 1 }

has _copy_from_build => (
    is      => 'lazy',
    isa     => 'ArrayRef[Str]',
    builder => sub {
        my ($self) = @_;

        my @copy = (qw{ LICENSE cpanfile });
        push @copy, 'Makefile.PL'
            if $self->is_app;

        return [ @copy ];
    },
);


sub release_plugins {
    my $self = shift @_;

    my @allow_dirty = qw{
        .gitignore
        .travis.yml
        Changes
        README.mkdn
        dist.ini
        weaver.ini
    };
    push @allow_dirty, $self->_copy_from_build->flatten;


    my @plugins = (
        qw{
            TestRelease
            CheckChangesHasContent
            CheckPrereqsIndexed
        },
        [ 'Git::Remote::Update' => GitFetchOrigin  => {
            remote_name   => 'origin',
            do_update     => 1,
        } ],
        [ 'Git::Remote::Check' => GitCheckReleaseBranchSync  => {
            remote_name   => 'origin',
            do_update     => 0,
            branch        => 'release/cpan',
            remote_branch => 'release/cpan',
        } ],
        [ 'Git::Remote::Check' => GitCheckMasterBranchSync => {
            remote_name   => 'origin',
            do_update     => 0,
            branch        => 'master',
            remote_branch => 'master',
        } ],
        [ 'Git::Check'      => { allow_dirty => [ @allow_dirty ] } ],
        [ 'Git::Commit'     => { allow_dirty => [ @allow_dirty ] } ],

        [ 'Test::CheckDeps' => { ':version' => '0.007', fatal => 1, level => 'suggests' } ],
        'CheckSelfDependency',
        'Travis::ConfigForReleaseBranch',
        'SchwartzRatio',

        [ 'Git::Tag' => { tag_format  => '%v', signed => $self->sign } ],

        [ 'Git::CommitBuild' => 'Git::CommitBuild::Build' => { } ],

        [ 'Git::CommitBuild' => 'Git::CommitBuild::Release' => {
            release_branch       => 'release/cpan',
            release_message      => 'Full build of CPAN release %v%t',
            multiple_inheritance => 1,
        }],

        [ 'Git::Push' => {
            push_to => [
                'origin',
                'origin refs/heads/release/cpan:refs/heads/release/cpan',
            ],
        }],
    );

    push @plugins, 'UploadToCPAN'
        unless $self->is_private;

    push @plugins, 'Signature',
        if $self->sign;
    push @plugins, [ Twitter => { hash_tags => '#perl #cpan' } ]
        if $self->tweet;
    push @plugins, [ InstallRelease => { install_command => 'cpanm .' } ]
        if $self->install_on_release;
    push @plugins, [ 'GitHub::Update' => { metacpan  => 1 } ]
        if $self->github;

    push @plugins,
        [ ArchiveRelease => { directory => 'releases' } ],
        'ConfirmRelease',
        ;

    return @plugins;
}


sub author_tests {
    my ($self) = @_;

    return () if $self->rapid_dev;

    return (
        [ 'Test::PodSpelling' => { stopwords => [ $self->stopwords ] } ],
        qw{
            ConsistentVersionTest
            PodCoverageTests
            PodSyntaxTests
            Test::NoTabs
            Test::EOL
            HasVersionTests
            Test::Compile
            NoSmartCommentsTests
            Test::Pod::LinkCheck
            RunExtraTests
            CheckExtraTests
        },
        [ 'Test::MinimumVersion' => { max_target_perl => '5.008008' } ],
    );
}


sub meta_provider_plugins {
    my ($self) = @_;

    my @plugins = (
        [ Authority => { authority => 'cpan:RSRCHBOY' } ],
        qw{ MetaConfig MetaJSON MetaYAML },
        [ MetaNoIndex => { directory => [ qw{ corpus t } ] } ],
        'MetaProvides::Package',
    );

    if ($self->github) {

        my $opts = { issues => 1 };

        $opts->{user} = $self->github_user
            if $self->set_github_user;

        push @plugins, [ GithubMeta => $opts ]
    }

    return @plugins;
}


sub configure {
    my $self = shift @_;

    $self->ensure_current;

    my $autoprereq_opts = $self->config_slice({ autoprereqs_skip => 'skip' });
    my $prepender_opts  = $self->config_slice({ prepender_skip   => 'skip' });

    # if we have a weaver.ini, use that; otherwise use our bundle
    my $podweaver
        = file('weaver.ini')->stat
        ? 'PodWeaver'
        : [ PodWeaver => { config_plugin => '@RSRCHBOY' } ]
        ;

    $self->add_plugins(
        [ NextRelease => { format => '%-8V  %{yyyy-MM-dd HH:mm:ss ZZZZ}d' }],
    );

    $self->add_plugins([ 'Git::NextVersion' =>
        #;first_version = 0.001       ; this is the default
        #;version_regexp  = ^v(.+)$   ; this is the default
        { version_regexp => '^(\d.\d+(_\d\d)?)(-TRIAL|)$' },
    ]);

    $self->add_plugins('ContributorsFromGit');

    $self->add_bundle('Git::CheckFor');

    $self->add_plugins(
        [ GatherDir => { exclude_filename => $self->_copy_from_build } ],
        [
            PromptIfStale => {
                phase   => 'build',
                modules => [ qw{
                    Dist::Zilla
                    Dist::Zilla::PluginBundle::RSRCHBOY
                }],
            },
        ],

        # this will be added by another plugin to the build
        [ PruneCruft => { except => '\.travis\.yml' } ],

        qw{
            Git::Describe
            ExecDir
            ShareDir
            MakeMaker
            Manifest
            SurgicalPkgVersion
            MinimumPerl
            ReportVersions::Tiny
        },
        [ AutoPrereqs => $autoprereq_opts ],
        [ Prepender   => $prepender_opts  ],

        $self->author_tests,
        $self->meta_provider_plugins,
        $self->release_plugins,

        'License',
        'CPANFile',

        [ ReadmeAnyFromPod  => ReadmeMarkdownInRoot => {
            type     => 'markdown',
            filename => 'README.mkdn',
            location => 'root',
        }],
        [ ReadmeAnyFromPod  => ReadmeTxt => {
            type     => 'text',
            filename => 'README',
        }],
        [ CopyFilesFromBuild => { copy => $self->_copy_from_build } ],

        ($self->is_task ? 'TaskWeaver' : $podweaver),
    );

    return;
}


sub ensure_current {
    my $self = shift @_;

    ### ensure all our CopyFromBuild files are known to git...
    for my $file ($self->_copy_from_build->flatten) {

        system "touch $file && git add $file && git commit -m 'dzil: autoadd $file' $file"
            unless $self->has_file_in_head($file);
    }

    system "git rm -f $_ && git commit -m 'dzil: autorm $_' $_"
        for grep { -f $_ } qw{ README.pod };

    return;
}



sub stopwords {

    return qw{
        AFAICT
        ABEND
        RSRCHBOY
        RSRCHBOY's
        gpg
        ini
        metaclass
        metaclasses
        parameterized
        parameterization
        subclasses
        coderef
    };
}

__PACKAGE__->meta->make_immutable;
!!42;

__END__

=pod

=encoding UTF-8

=for :stopwords Chris Weyl Bowers Neil Romanov Sergey GitHub Plugins

=for :stopwords Wishlist flattr flattr'ed gittip gittip'ed

=head1 NAME

Dist::Zilla::PluginBundle::RSRCHBOY - Zilla your distributions like RSRCHBOY!

=head1 VERSION

This document describes version 0.055 of Dist::Zilla::PluginBundle::RSRCHBOY - released December 27, 2014 as part of Dist-Zilla-PluginBundle-RSRCHBOY.

=head1 SYNOPSIS

    # in your dist.ini...
    [@RSRCHBOY]

=head1 DESCRIPTION

This is RSRCHBOY's current L<Dist::Zilla> C<dist.ini> config for his packages.
He's still figuring this all out, so it's probably wise to not depend on
this being too terribly consistent/sane until the version gets to 1.

=head1 METHODS

=head2 release_plugins

Plugin configuration for public release.

=head2 author_tests

=head2 meta_provider_plugins

Plugins that mess about with what goes into META.*.

=head2 configure

Preps plugin lists / config; see L<Dist::Zilla::Role::PluginBundle::Easy>.

=head2 ensure_current

Sometimes things change.  (I know, I know, the horror!)  This seeks to
minimize that pain by automatically making what changes it can.

=head2 stopwords

A list of words our POD spell checker should ignore.

=for Pod::Coverage configure

=head1 OPTIONS

=head2 sign (boolean; default: true)

On release, use your gpg key to sign the version tag created (if you're using
git) and also generate a SIGNATURE file.

See also L<Dist::Zilla::Plugin::Signature>.

=head2 tweet (boolean; default: true)

If set to a true value, we'll use L<Dist::Zilla::Plugin::Twitter> to tweet
when a release occurs.

=head2 github (boolean; default: true)

This enables various GitHub related plugins to update distribution and GitHub
metadata automatically.

=head2 install_on_release (boolean; default: true)

After a release, install the distribution locally. Our default install command
is (from inside the built release directory):

    cpanm .

You can change this by setting the C<InstallRelease.install_command> option.

=head1 BUNDLED PLUGIN OPTIONS

It's possible to pass options to our bundled plugins directly:

    ; format is Plugin::Name.option
    [@RSRCHBOY]
    GatherDir.exclude_filename = cpanfile

For information on specific plugins and their options, you should refer to the
documentation of L<Dist::Zilla::Role::PluginBundle::Config::Slicer>.

=head1 SEE ALSO

Please see those modules/websites for more information related to this module.

=over 4

=item *

L<Dist::Zilla::Role::PluginBundle::Easy|Dist::Zilla::Role::PluginBundle::Easy>

=item *

L<Dist::Zilla::Role::PluginBundle::PluginRemover|Dist::Zilla::Role::PluginBundle::PluginRemover>

=item *

L<Dist::Zilla::Role::PluginBundle::Config::Slicer|Dist::Zilla::Role::PluginBundle::Config::Slicer>

=item *

L<Config::MVP::Slicer|Config::MVP::Slicer>

=back

=head1 SOURCE

The development version is on github at L<http://https://github.com/RsrchBoy/dist-zilla-pluginbundle-rsrchboy>
and may be cloned from L<git://https://github.com/RsrchBoy/dist-zilla-pluginbundle-rsrchboy.git>

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website
https://github.com/RsrchBoy/dist-zilla-pluginbundle-rsrchboy/issues

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Chris Weyl <cweyl@alumni.drew.edu>

=head2 I'm a material boy in a material world

=begin html

<a href="https://www.gittip.com/RsrchBoy/"><img src="https://raw.githubusercontent.com/gittip/www.gittip.com/master/www/assets/%25version/logo.png" /></a>
<a href="http://bit.ly/rsrchboys-wishlist"><img src="http://wps.io/wp-content/uploads/2014/05/amazon_wishlist.resized.png" /></a>
<a href="https://flattr.com/submit/auto?user_id=RsrchBoy&url=https%3A%2F%2Fgithub.com%2FRsrchBoy%2Fdist-zilla-pluginbundle-rsrchboy&title=RsrchBoy's%20CPAN%20Dist-Zilla-PluginBundle-RSRCHBOY&tags=%22RsrchBoy's%20Dist-Zilla-PluginBundle-RSRCHBOY%20in%20the%20CPAN%22"><img src="http://api.flattr.com/button/flattr-badge-large.png" /></a>

=end html

Please note B<I do not expect to be gittip'ed or flattr'ed for this work>,
rather B<it is simply a very pleasant surprise>. I largely create and release
works like this because I need them or I find it enjoyable; however, don't let
that stop you if you feel like it ;)

L<Flattr this|https://flattr.com/submit/auto?user_id=RsrchBoy&url=https%3A%2F%2Fgithub.com%2FRsrchBoy%2Fdist-zilla-pluginbundle-rsrchboy&title=RsrchBoy's%20CPAN%20Dist-Zilla-PluginBundle-RSRCHBOY&tags=%22RsrchBoy's%20Dist-Zilla-PluginBundle-RSRCHBOY%20in%20the%20CPAN%22>,
L<gittip me|https://www.gittip.com/RsrchBoy/>, or indulge my
L<Amazon Wishlist|http://bit.ly/rsrchboys-wishlist>...  If you so desire.

=head1 CONTRIBUTORS

=for stopwords Neil Bowers Sergey Romanov

=over 4

=item *

Neil Bowers <neil@bowers.com>

=item *

Sergey Romanov <complefor@rambler.ru>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by Chris Weyl.

This is free software, licensed under:

  The GNU Lesser General Public License, Version 2.1, February 1999

=cut
