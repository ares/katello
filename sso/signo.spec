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

%global homedir %{_datarootdir}/%{name}
%global datadir %{_sharedstatedir}/%{name}
%global confdir deploy

Name:           signo
Version:        0.0.1
Release:        1%{?dist}
Summary:        A package for web based SSO for various applications
BuildArch:      noarch

Group:          Applications/Internet
License:        GPLv2
URL:            https://fedorahosted.org/katello/wiki/SingleSignOn
Source0:        https://fedorahosted.org/releases/s/i/signo/%{name}-%{version}.tar.gz

Requires:       %{name}
Requires:       httpd
Requires:       mod_ssl
Requires:       rubygems
Requires:       rubygem(logging) >= 1.8.0
Requires:       rubygem(rails) >= 3.2
Requires:       rubygem(haml) >= 3.1.2
Requires:       rubygem(haml-rails)
Requires:       rubygem(compass)
Requires:       rubygem(compass-rails)
Requires:       rubygem(net-ldap)
Requires:       rubygem(i18n_data) >= 0.2.6
Requires:       rubygem(gettext_i18n_rails)
Requires:       rubygem(ldap_fluff)
Requires:       rubygem(alchemy) >= 1.0.1
Requires:       rubygem(ruby-openid)
Requires:       rubygem(thin)

%if 0%{?rhel} == 6 || 0%{?fedora} < 17
Requires: ruby(abi) = 1.8
%else
Requires: ruby(abi) = 1.9.1
%endif
Requires: ruby

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
Requires:        %{name} = %{version}-%{release}
Requires:        rubygem(gettext) >= 1.9.3

%description devel
Rake tasks and dependecies for Signo developers

%package devel-test
Summary:         Signo devel support (testing)
BuildArch:       noarch
Requires:        %{name} = %{version}-%{release}
Requires:        %{name}-devel = %{version}-%{release}
# dependencies from bundler.d/test.rb
Requires:        rubygem(webmock)
Requires:        rubygem(minitest) <= 4.5.0
Requires:        rubygem(minitest-rails)

BuildRequires:        rubygem(minitest)
BuildRequires:        rubygem(minitest-rails)

%description devel-test
Rake tasks and dependecies for Signo developers, which enables
testing.

%prep
%setup -q

%build
export RAILS_ENV=build

# create empty sso.yml config file
echo "# overwrite config options in this file instead of changing sso_defaults.yml" > config/sso.yml

%if ! 0%{?fastbuild:1}
    #generate Rails JS/CSS/... assets
    echo Generating Rails assets...
    LC_ALL="en_US.UTF-8" rake assets:precompile

    #create mo-files for L10n (since we miss build dependencies we can't use #rake gettext:pack)
    echo Generating gettext files...
    LC_ALL=C ruby -e 'require "rubygems"; require "gettext/tools"; GetText.create_mofiles(:po_root => "locale", :mo_root => "locale")' 2>&1 \
      | sed -e '/Warning: obsolete msgid exists./,+1d' | sed -e '/Warning: fuzzy message was ignored./,+1d'
%endif

%install
#prepare dir structure
install -d -m0755 %{buildroot}%{homedir}
install -d -m0755 %{buildroot}%{datadir}
install -d -m0755 %{buildroot}%{datadir}/tmp
install -d -m0755 %{buildroot}%{datadir}/tmp/pids
install -d -m0755 %{buildroot}%{datadir}/config
install -d -m0755 %{buildroot}%{datadir}/openid-store
install -d -m0755 %{buildroot}%{_sysconfdir}/%{name}

install -d -m0755 %{buildroot}%{_localstatedir}/log/%{name}

# clean the application directory before installing
[ -d tmp ] && rm -rf tmp

#copy the application to the target directory
mkdir .bundle
cp -R .bundle Gemfile bundler.d Rakefile app config config.ru db lib locale public script test vendor %{buildroot}%{homedir}

#copy init scripts and sysconfigs
install -Dp -m0644 %{confdir}/%{name}.sysconfig %{buildroot}%{_sysconfdir}/sysconfig/%{name}
install -Dp -m0755 %{confdir}/%{name}.init %{buildroot}%{_initddir}/%{name}
install -Dp -m0644 %{confdir}/%{name}.httpd.conf %{buildroot}%{_sysconfdir}/httpd/conf.d/%{name}.conf
install -Dp -m0644 %{confdir}/thin.yml %{buildroot}%{_sysconfdir}/%{name}/

#overwrite config files with symlinks to /etc/signo
ln -svf %{_sysconfdir}/%{name}/sso.yml %{buildroot}%{homedir}/config/sso.yml

#create symlinks for data
ln -sv %{_localstatedir}/log/%{name} %{buildroot}%{homedir}/log
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
/sbin/chkconfig --add %{name}

#Generate secret token if the file does not exist
#(this must be called both for installation and upgrade)
TOKEN=/etc/signo/secret_token
# this file must not be world readable at generation time
umask 0077
test -f $TOKEN || (echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c128) > $TOKEN \
    && chmod 600 $TOKEN && chown signo:signo $TOKEN)

%posttrans
/sbin/service %{name} condrestart >/dev/null 2>&1 || :

%files
%ghost %attr(600, signo, signo) %{_sysconfdir}/%{name}/secret_token
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
%{_sysconfdir}/%{name}/thin.yml
%{_sysconfdir}/rc.d/init.d/%{name}
%{_sysconfdir}/httpd/conf.d/%{name}.conf
%{_sysconfdir}/sysconfig/%{name}


%defattr(-, signo, signo)
%dir %{homedir}
%attr(750, signo, signo) %{_localstatedir}/log/%{name}
%{datadir}
%ghost %attr(640, signo, signo) %{_localstatedir}/log/%{name}/production.log

%files devel

%files devel-test

%pre
# Add the "signo" user and group
getent group %{name} >/dev/null || groupadd -r %{name} -g 187
getent passwd %{name} >/dev/null || \
    useradd -r -g %{name} -d %{homedir} -u 187 -s /sbin/nologin -c "Signo" %{name}
exit 0

%preun
if [ $1 -eq 0 ] ; then
    /sbin/service %{name} stop >/dev/null 2>&1
    /sbin/chkconfig --del %{name}
fi
