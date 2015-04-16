docker_cleanup() {
    echo "Cleanup leftover docker containers if any ..."
    docker ps -aq -f status=exited | xargs -r docker rm
    docker images | grep '^<none>' | awk '{print $3}' | xargs -r docker rmi
}

yum_conf_install_docs() {
    cp /etc/yum.conf /tmp/
    sed -e 's|\(.*tsflags.*\)nodocs\(.*\)|\1\2|' -i /etc/yum.conf
      # cp /tmp/yum.conf /etc/  # do not restore so all packages install docs
}

docker_setup_user() {
  local dev_uid=$1
  shift;

  echo "creating dev user with uid: $dev_uid"

  local existing_user=$(getent passwd |grep "x:$dev_uid:[0-9]" | cut -f1 -d:)
  echo "found an user: $existing_user"
  test -z "$existing_user" || {
    echo "Deleting user: $existing_user"
    userdel $existing_user
  }

  useradd -u $dev_uid dev
  chown -R dev /code
}

docker_setup_container() {
    local dev_uid=$1
    mute_success docker_setup_user $dev_uid
    mute_success yum_conf_install_docs
    mute_success yum repolist
    mute_success yum install -y deltarpm
    if rpm -qi setup > /dev/null; then
        mute_success yum reinstall -y setup
    else
        mute_success yum install -y setup
    fi
    mute_success yum upgrade -y
}

