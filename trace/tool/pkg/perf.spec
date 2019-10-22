# Reference:
# 1) https://elrepo.org/linux/kernel/el7/SRPMS/kernel-ml-5.3.7-1.el7.elrepo.nosrc.rpm
# 2) make rpm-pkg, then check kernel.spec
# 3) https://build.opensuse.org/package/view_file/devel:tools/perf/perf.spec?expand=1
#
# Steps:
# 1) cd ${KERNEL_SRC_PATH}
# 2) make perf-targz-src-pkg
# 3) mkdir temp_dir
# 4) mv perf-5.3.0.tar.gz temp_dir; cd temp_dir
# 5) tar xvzf perf-5.3.0.tar.gz
# 6) cp ../COPYING perf-5.3.0; cp ../README perf-5.3.0; cp ../CREDITS perf-5.3.0
# 7) cp ${this_file} perf-5.3.0
# 8) mv perf-5.3.0.tar.gz perf-5.3.0.tar.gz_bak
# 9) tar cvzf perf-5.3.0.tar.gz perf-5.3.0
# 10) rpmdev-setuptree
# 11) cp ${this_file} $HOME/rpmbuild/SPECS; cp perf-5.3.0.tar.gz $HOME/rpmbuild/SOURCES
# 12) rpmbuild -ba ~/rpmbuild/SPECS/perf.spec

Name: perf
Summary: Performance Monitoring Tools for Linux
#%define version %(rpm -q --qf '%%{VERSION}' kernel-headers)
Version: 5.3.0
Release: 1
Group: Development/Tools/Debuggers
License: GPL-2.0-only
Source0: perf-5.3.0.tar.gz

BuildRequires: binutils-devel, elfutils-devel
BuildRequires: perl(ExtUtils::Embed), python-devel, slang-devel
BuildRequires: asciidoc xmlto

%description -n perf
This package provides a userspace tool 'perf', which monitors performance for
either unmodified binaries or the entire system. It requires a Linux kernel
which includes the Performance Counters for Linux (PCL) subsystem (>= 2.6.31).
This subsystem utilizes the Performance Monitoring Unit (PMU) / hardware
counters of the underlying cpu architecture (if supported).

%package -n python-perf
Summary: Python bindings for applications that will manipulate perf events.
Group: Development/Libraries
%description -n python-perf
This package provides a module that permits applications written in the
Python programming language to use the interface to manipulate perf events.

%{!?python_sitearch: %global python_sitearch %(%{__python} -c "from distutils.sysconfig import get_python_lib; print get_python_lib(1)")}

%prep
%setup -q

%build
%global perf_make \
    %{__make} -s -C tools/perf %{?_smp_mflags} prefix=%{_prefix} lib=%{_lib} WERROR=0 HAVE_CPLUS_DEMANGLE=1 NO_GTK2=1 NO_LIBBABELTRACE=1 NO_LIBUNWIND=1 NO_LIBZSTD=1 NO_PERF_READ_VDSO32=1 NO_PERF_READ_VDSOX32=1 NO_STRLCPY=1

%{perf_make} all
%{perf_make} man

%install
%{perf_make} DESTDIR=$RPM_BUILD_ROOT install
%{perf_make} DESTDIR=$RPM_BUILD_ROOT install-python_ext
%{perf_make} DESTDIR=$RPM_BUILD_ROOT try-install-man
mkdir -p %{buildroot}/%{_docdir}/perf/examples/bpf
mv %{buildroot}/usr/lib/perf/include/bpf/* %{buildroot}/%{_docdir}/perf/examples/bpf
mv %{buildroot}/usr/lib/perf/examples/bpf/* %{buildroot}/%{_docdir}/perf/examples/bpf

%clean
rm -rf %{buildroot}

%files -n perf
%defattr(-, root, root)
%{_bindir}/perf
%{_bindir}/trace
%{_libdir}/libperf-jvmti.so
%dir %{_docdir}/perf
%dir %{_docdir}/perf/examples
%dir %{_docdir}/perf/examples/bpf
%{_docdir}/perf/examples/bpf/*

%dir %{_libdir}/traceevent
%dir %{_libdir}/traceevent/plugins
%{_libdir}/traceevent/plugins/*
%dir %{_libexecdir}/perf-core
%{_libexecdir}/perf-core/*
%{_mandir}/man[1-8]/perf*
%attr(0644, -, -) %{_sysconfdir}/bash_completion.d/perf
%dir %{_datadir}/perf-core/strace/groups
%{_datadir}/perf-core/strace/groups/*
%{_datadir}/doc/perf-tip/*
%attr(0644, root, root) %doc COPYING CREDITS README tools/perf/design.txt

%files -n python-perf
%defattr(-,root,root)
%{python_sitearch}

%changelog

