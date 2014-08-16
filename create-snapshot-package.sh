#!/bin/zsh

set -u
set -e

run()
{
  "$@"
  if test $? -ne 0; then
    echo "Failed $@"
    exit 1
  fi
}

keep_n_days=7
mysql_version=5.6.19

today=$(date +%Y.%m.%d)
mysql_base="mysql-${mysql_version}"

run mkdir -p ~/work/

output_dir="${HOME}/public/nightly/"
run mkdir -p "${output_dir}"

#rm -rf ~/work/nightly/
#mkdir -p ~/work/nightly/

export PKG_CONFIG_PATH=$HOME/work/nightly/lib/pkgconfig

build_mysql() {
  run cd ~/work/
  if [ -d "${mysql_base}" ]; then
    return 0
  fi

  mysql_tar_gz="${mysql_base}.tar.gz"
  if [ ! -f "${mysql_tar_gz}" ]; then
    download_base=http://ftp.jaist.ac.jp/pub/mysql/Downloads/MySQL-5.6
    run wget --quiet "${download_base}/${mysql_tar_gz}"
  fi

  run tar xf "${mysql_tar_gz}"
  run cd "${mysql_base}"
  run cmake . -DWITH_DEBUG=yes -DCMAKE_INSTALL_PREFIX=$HOME/work/nightly \
    > cmake.log
  run make > make.log 2> make.error.log
}

create_nightly_build() {
  github_org=$1; shift
  project_name=$1; shift
  need_install=$1; shift
  run cd ~/work
  if [ ! -d ${project_name} ]; then
    run git clone --quiet --recursive \
      https://github.com/${github_org}/${project_name}.git
    run cd ${project_name}
    run ./autogen.sh > /dev/null
    run cd -
  else
    run cd ${project_name}
    run git checkout --quiet .
    run git pull --quiet --rebase
    run git submodule update --init
    run ./autogen.sh > /dev/null
    run cd -
  fi
  run cd ${project_name}
  released_version=$(git describe --abbrev=0 | sed -e 's/^v//')
  run cd -
  version="${released_version}.${today}"
  run rm -rf ${project_name}.build
  run mkdir -p ${project_name}.build
  run cd ${project_name}.build
  run ../${project_name}/configure \
    CFLAGS="-O0" CXXFLAGS="-O0" \
    --prefix=$HOME/work/nightly \
    "$@" \
    > configure.log
  run make > make.log 2> make.error.log
  if [ "$need_install" = "yes" ]; then
    run make install > /dev/null
  fi
  run make dist > /dev/null
  run mkdir -p tmp
  cd tmp
  run tar xf ../*.tar.gz
  run mv ${project_name}-* ${project_name}-${version}
  run tar cfz ${project_name}-${version}.tar.gz ${project_name}-${version}
  run mv ${project_name}-${version}.tar.gz ~/public/nightly/
}

package_mariadb_with_mroonga() {
  run cd ~/work/mroonga.build/packages/source
  groonga_tar_gz=$(echo ~/public/nightly/groonga-[0-9]*.${today}.tar.gz)
  groonga_normalizer_mysql_tar_gz=$(echo ~/public/nightly/groonga-normalizer-mysql-[0-9]*.${today}.tar.gz)
  run mkdir -p tmp/
  run cp ${groonga_tar_gz} tmp/
  run cp ${groonga_normalizer_mysql_tar_gz} tmp/
  groonga_version=${groonga_tar_gz:t:r:r:s/groonga-//}
  groonga_normalizer_mysql_version=${groonga_normalizer_mysql_tar_gz:t:r:r:s/groonga-normalizer-mysql-//}
  run make archive \
      GROONGA_VERSION=${groonga_version} \
      GROONGA_NORMALIZER_MYSQL_VERSION=${groonga_normalizer_mysql_version} \
      > /dev/null
  for archive in files/mariadb-*.zip; do
    run rm -rf tmp
    run mkdir -p tmp
    run cd tmp
    run unzip -q ../${archive}
    base_name=$(echo mariadb-*)
    new_base_name=${base_name}.${today}
    run mv ${base_name} ${new_base_name}
    run zip -q -r ${new_base_name}.zip ${new_base_name}
    run mv ${new_base_name}.zip ~/public/nightly/
    run cd -
  done
  for archive in files/mariadb-*.tar.gz; do
    run rm -rf tmp
    run mkdir -p tmp
    run cd tmp
    run tar xzf ../${archive}
    base_name=$(echo mariadb-*)
    new_base_name=${base_name}.${today}
    run mv ${base_name} ${new_base_name}
    run tar czf ${new_base_name}.tar.gz ${new_base_name}
    run mv ${new_base_name}.tar.gz ~/public/nightly/
    run cd -
  done
}

create_nightly_build groonga groonga yes \
    --without-cutter \
    --enable-document \
    --with-ruby \
    --enable-mruby
create_nightly_build groonga groonga-normalizer-mysql yes
build_mysql
create_nightly_build mroonga mroonga no \
  --without-cutter \
  --enable-document \
  --with-mysql-source="$HOME/work/${mysql_base}" \
  --with-mysql-config="$HOME/work/${mysql_base}/scripts/mysql_config"
package_mariadb_with_mroonga

run find "${output_dir}/" -maxdepth 1 -type f -ctime +${keep_n_days} -print0 | \
  run xargs --null --no-run-if-empty rm
