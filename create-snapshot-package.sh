#!/bin/zsh

set -u
set -e

keep_n_days=7
mysql_version=5.6.19

today=$(date +%Y.%m.%d)
mysql_base="mysql-${mysql_version}"

mkdir -p ~/work/

output_dir="${HOME}/public/nightly/"
mkdir -p "${output_dir}"

#rm -rf ~/work/nightly/
#mkdir -p ~/work/nightly/

export PKG_CONFIG_PATH=$HOME/work/nightly/lib/pkgconfig

build_mysql() {
  cd ~/work/
  if [ -d "${mysql_base}" ]; then
    return 0
  fi

  mysql_tar_gz="${mysql_base}.tar.gz"
  if [ ! -f "${mysql_tar_gz}" ]; then
    download_base=http://ftp.jaist.ac.jp/pub/mysql/Downloads/MySQL-5.6
    wget --quiet "${download_base}/${mysql_tar_gz}"
  fi

  tar xf "${mysql_tar_gz}"
  cd "${mysql_base}"
  cmake . -DWITH_DEBUG=yes -DCMAKE_INSTALL_PREFIX=$HOME/work/nightly \
    > cmake.log
  make > make.log 2> make.error.log
}

create_nightly_build() {
  github_org=$1; shift
  project_name=$1; shift
  need_install=$1; shift
  cd ~/work
  if [ ! -d ${project_name} ]; then
    git clone --quiet --recursive https://github.com/${github_org}/${project_name}.git
    cd ${project_name}
    ./autogen.sh > /dev/null
    cd -
  else
    cd ${project_name}
    git checkout --quiet .
    git pull --quiet --rebase
    git submodule update --init
    ./autogen.sh > /dev/null
    cd -
  fi
  cd ${project_name}
  released_version=$(git describe --abbrev=0 | sed -e 's/^v//')
  cd -
  version="${released_version}.${today}"
  rm -rf ${project_name}.build
  mkdir -p ${project_name}.build
  cd ${project_name}.build
  ../${project_name}/configure \
    CFLAGS="-O0" CXXFLAGS="-O0" \
    --prefix=$HOME/work/nightly \
    "$@" \
    > configure.log
  make > make.log 2> make.error.log
  if [ "$need_install" = "yes" ]; then
    make install > /dev/null
  fi
  make dist > /dev/null
  mkdir -p tmp
  cd tmp
  tar xf ../*.tar.gz
  mv ${project_name}-* ${project_name}-${version}
  tar cfz ${project_name}-${version}.tar.gz ${project_name}-${version}
  mv ${project_name}-${version}.tar.gz ~/public/nightly/
}

package_mariadb_with_mroonga() {
  cd ~/work/mroonga.build/packages/source
  groonga_tar_gz=$(echo ~/public/nightly/groonga-[0-9]*.${today}.tar.gz)
  groonga_normalizer_mysql_tar_gz=$(echo ~/public/nightly/groonga-normalizer-mysql-[0-9]*.${today}.tar.gz)
  mkdir -p tmp/
  cp ${groonga_tar_gz} tmp/
  cp ${groonga_normalizer_mysql_tar_gz} tmp/
  groonga_version=${groonga_tar_gz:t:r:r:s/groonga-//}
  groonga_normalizer_mysql_version=${groonga_normalizer_mysql_tar_gz:t:r:r:s/groonga-normalizer-mysql-//}
  make archive \
      GROONGA_VERSION=${groonga_version} \
      GROONGA_NORMALIZER_MYSQL_VERSION=${groonga_normalizer_mysql_version} \
      > /dev/null
  for archive in files/mariadb-*.zip; do
    rm -rf tmp
    mkdir -p tmp
    cd tmp
    unzip -q ../${archive}
    base_name=$(echo mariadb-*)
    new_base_name=${base_name}.${today}
    mv ${base_name} ${new_base_name}
    zip -q -r ${new_base_name}.zip ${new_base_name}
    mv ${new_base_name}.zip ~/public/nightly/
    cd -
  done
  for archive in files/mariadb-*.tar.gz; do
    rm -rf tmp
    mkdir -p tmp
    cd tmp
    tar xzf ../${archive}
    base_name=$(echo mariadb-*)
    new_base_name=${base_name}.${today}
    mv ${base_name} ${new_base_name}
    tar czf ${new_base_name}.tar.gz ${new_base_name}
    mv ${new_base_name}.tar.gz ~/public/nightly/
    cd -
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

find "${output_dir}/" -maxdepth 1 -type f -ctime +${keep_n_days} -print0 | \
  xargs --null --no-run-if-empty rm
