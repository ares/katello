%{?scl:%scl_package signo}
%{!?scl:%global pkg_name %{name}}

# Copyright 2011 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

%global homedir %{_datarootdir}/%{pkg_name}
%global datadir %{_sharedstatedir}/%{pkg_name}
%global confdir deploy

Name:           signo
Version:        0.0.2
Release:        1%{?dist}
Summary:        A package for web based SSO for various applications
BuildArch:      noarch

Group:          Applications/Internet
License:        GPLv2
URL:            https://fedorahosted.org/katello/wiki/SingleSignOn
Source0:        https://fedorahosted.org/releases/s/i/signo/%{pkg_name}-%{version}.tar.gz

Requires:       httpd
Requires:       mod_ssl
Requires:       %{?scl_prefix}rubygems
Requires:       %{?scl_prefix}rubygem(logging) >= 1.8.0
Requires:       %{?scl_prefix}rubygem(rails) >= 3.2
Requires:       %{?scl_prefix}rubygem(haml) >= 3.1.2
Requires:       %{?scl_prefix}rubygem(haml-rails)
Requires:       %{?scl_prefix}rubygem(compass)
Requires:       %{?scl_prefix}rubygem(compass-rails)
Requires:       %{?scl_prefix}rubygem(net-ldap)
Requires:       %{?scl_prefix}rubygem(i18n_data) >= 0.2.6
Requires:       %{?scl_prefix}rubygem(gettext_i18n_rails)
Requires:       %{?scl_prefix}rubygem(ldap_fluff)
Requires:       %{?scl_prefix}rubygem(alchemy) >= 1.0.1
Requires:       %{?scl_prefix}rubygem(ruby-openid)
Requires:       %{?scl_prefix}rubygem(thin)

Requires: %{?scl_prefix}ruby(abi) = 1.9.1
Requires: %{?scl_prefix}ruby

Requires(pre):    shadow-utils
Requires(preun):  chkconfig
Requires(preun):  initscripts
Requires(post):   chkconfig
Requires(postun): initscripts coreutils sed

%description
Web based SSO for various applications

%package devel
Summary:         Signo devel support
BuildArch:       noarch
Requires:        %{pkg_name} = %{version}-%{release}
Requires:        %{?scl_prefix}rubygem(gettext) >= 1.9.3

%description devel
Rake tasks and dependecies for Signo developers

%package devel-test
Summary:         Signo devel support (testing)
BuildArch:       noarch
Requires:        %{pkg_name} = %{version}-%{release}
Requires:        %{pkg_name}-devel = %{version}-%{release}
# dependencies from bundler.d/test.rb
Requires:        %{?scl_prefix}rubygem(webmock)
Requires:        %{?scl_prefix}rubygem(minitest) <= 4.5.0
Requires:        %{?scl_prefix}rubygem(minitest-rails)

BuildRequires:        %{?scl_prefix}rubygem(minitest)
BuildRequires:        %{?scl_prefix}rubygem(minitest-rails)

%description devel-test
Rake tasks and dependecies for Signo developers, which enables
testing.

%prep
%setup -n %{pkg_name}-%{version} -q

%build
export RAILS_ENV=build

# create empty sso.yml config file
echo "# overwrite config options in this file instead of changing sso_defaults.yml" > config/sso.yml

%if ! 0%{?fastbuild:1}
%{?scl:scl enable %{scl} "}
    #generate Rails JS/CSS/... assets
    echo Generating Rails assets...
    LC_ALL="en_US.UTF-8" rake assets:precompile

    #create mo-files for L10n (since we miss build dependencies we can't use #rake gettext:pack)
    echo Generating gettext files...
    LC_ALL=C ruby -e 'require "rubygems"; require "gettext/tools"; GetText.create_mofiles(:po_root => "locale", :mo_root => "locale")' 2>&1 \
      | sed -e '/Warning: obsolete msgid exists./,+1d' | sed -e '/Warning: fuzzy message was ignored./,+1d'
%{?scl:"}
%endif

%install
#prepare dir structure
install -d -m0755 %{buildroot}%{homedir}
install -d -m0755 %{buildroot}%{datadir}
install -d -m0755 %{buildroot}%{datadir}/tmp
install -d -m0755 %{buildroot}%{datadir}/tmp/pids
install -d -m0755 %{buildroot}%{datadir}/config
install -d -m0755 %{buildroot}%{datadir}/openid-store
install -d -m0755 %{buildroot}%{_sysconfdir}/%{pkg_name}

install -d -m0755 %{buildroot}%{_localstatedir}/log/%{pkg_name}

# clean the application directory before installing
[ -d tmp ] && rm -rf tmp

#copy the application to the target directory
mkdir .bundle
cp -R .bundle Gemfile bundler.d Rakefile app config config.ru db lib locale public script test vendor %{buildroot}%{homedir}

#copy init scripts and sysconfigs
install -Dp -m0644 %{confdir}/%{pkg_name}.sysconfig %{buildroot}%{_sysconfdir}/sysconfig/%{pkg_name}
install -Dp -m0755 %{confdir}/%{pkg_name}.init %{buildroot}%{_initddir}/%{pkg_name}
install -Dp -m0644 %{confdir}/%{pkg_name}.httpd.conf %{buildroot}%{_sysconfdir}/httpd/conf.d/%{pkg_name}.conf
install -Dp -m0644 %{confdir}/thin.yml %{buildroot}%{_sysconfdir}/%{pkg_name}/

#overwrite config files with symlinks to /etc/signo
ln -svf %{_sysconfdir}/%{pkg_name}/sso.yml %{buildroot}%{homedir}/config/sso.yml

#create symlinks for data
ln -sv %{_localstatedir}/log/%{pkg_name} %{buildroot}%{homedir}/log
ln -sv %{datadir}/openid-store %{buildroot}%{homedir}/db/openid-store
ln -sv %{datadir}/tmp %{buildroot}%{homedir}/tmp

#remove files which are not needed in the homedir
rm -f %{buildroot}%{homedir}/bundler.d/.gitkeep
rm -f %{buildroot}%{homedir}/public/stylesheets/.gitkeep
rm -f %{buildroot}%{homedir}/vendor/plugins/.gitkeep
rm -f %{buildroot}%{homedir}/lib/assets/.gitkeep

#correct permissions
find %{buildroot}%{homedir} -type d -print0 | xargs -0 chmod 755
find %{buildroot}%{homedir} -type f -print0 | xargs -0 chmod 644
chmod +x %{buildroot}%{homedir}/script/*

%post

#Add /etc/rc*.d links for the script
/sbin/chkconfig --add %{pkg_name}

#Generate secret token if the file does not exist
#(this must be called both for installation and upgrade)
TOKEN=/etc/signo/secret_token
# this file must not be world readable at generation time
umask 0077
test -f $TOKEN || (echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c128) > $TOKEN \
    && chmod 600 $TOKEN && chown signo:signo $TOKEN)

%posttrans
/sbin/service %{pkg_name} condrestart >/dev/null 2>&1 || :

%files
%ghost %attr(600, signo, signo) %{_sysconfdir}/%{pkg_name}/secret_token
%dir %{homedir}/app
%{homedir}/app/controllers
%{homedir}/app/helpers
%{homedir}/app/mailers
%dir %{homedir}/app/models
%dir %{homedir}/app/models/backends
%{homedir}/app/models/backends/*.rb
%{homedir}/app/models/*.rb
%{homedir}/app/assets
%{homedir}/app/views
%{homedir}/config
%{homedir}/db
%{homedir}/db/seeds.rb
%{homedir}/lib
%{homedir}/locale
%{homedir}/log
%{homedir}/public/*.html
%{homedir}/public/*.txt
%{homedir}/public/*.ico
%{homedir}/public/assets
%{homedir}/public/javascripts
%{homedir}/public/stylesheets
%{homedir}/script
%{homedir}/test
%{homedir}/tmp
%{homedir}/vendor
%dir %{homedir}/.bundle
%{homedir}/config.ru
%{homedir}/Gemfile
%{homedir}/Rakefile
%{_sysconfdir}/%{pkg_name}/thin.yml
%{_sysconfdir}/rc.d/init.d/%{pkg_name}
%{_sysconfdir}/httpd/conf.d/%{pkg_name}.conf
%{_sysconfdir}/sysconfig/%{pkg_name}


%defattr(-, signo, signo)
%dir %{homedir}
%attr(750, signo, signo) %{_localstatedir}/log/%{pkg_name}
%{datadir}
%ghost %attr(640, signo, signo) %{_localstatedir}/log/%{pkg_name}/production.log

%files devel

%files devel-test

%pre
# Add the "signo" user and group
getent group %{pkg_name} >/dev/null || groupadd -r %{pkg_name} -g 187
getent passwd %{pkg_name} >/dev/null || \
    useradd -r -g %{pkg_name} -d %{homedir} -u 187 -s /sbin/nologin -c "Signo" %{pkg_name}
exit 0

%preun
if [ $1 -eq 0 ] ; then
    /sbin/service %{pkg_name} stop >/dev/null 2>&1
    /sbin/chkconfig --del %{pkg_name}
fi


