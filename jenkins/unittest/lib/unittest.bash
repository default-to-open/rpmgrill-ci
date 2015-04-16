print_usage() {

    read -r -d '' help <<-EOF_HELP || true
Usage:
    $( basename $0)  PATH/TO/rpmgrill
EOF_HELP

    echo -e "$help"
    return 0
}

unittest_validate() {

    test -z "$distro" && {
        log.error "docker container to execute tests is not provided"
        return 1
    }

    test -z "$rpmgrill_path" && {
        log.error "rpmgrill path must be passed to the script"
        return 1
    }

    is_dir $rpmgrill_path || {
        log.error "rpmgrill path '$rpmgrill_path' is invalid"
        return 1
    }

    return 0
}

unit_test() {
    cover -delete || true
    echo "Running: prove -lrcf t/"

    DEBUG=true HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lrcf t/
    local exit_code=$?
    cover -report html
    return $exit_code
}

unittest_run(){
    local distro=${1:-''}
    local rpmgrill_path=${2:-''}

    unittest_validate || exit 1
    shift 2

    # relative to  absolute path
    rpmgrill_path=$(readlink -f $rpmgrill_path)
    cd $rpmgrill_path

    ### start with cleaning up & docker artifacts ###
    is_defined JENKINS_HOME && {    ## ensure it
        mute_success docker_cleanup
        mute_success docker pull $distro
    }

    log.info "Running tests in container: ${BLUE}$distro"

    docker run --rm -i -v $PWD:/code $distro bash <<-EOF_DOCKER
    set -eu

    ### import functions used into the container ###
    $(typeset -f mute_success);
    $(typeset -f yum_conf_install_docs);
    $(typeset -f docker_setup_user);
    $(typeset -f docker_setup_container);
    $(typeset -f docker_install_dependencies);

    ### setup ###
    docker_setup_container $UID
    docker_install_dependencies

    ### run test a dev user ###
    ### import execute into this dev users shell ###
    su - dev
    $(typeset -f unit_test);
    cd /code

    ### run actual test ###
    unit_test
EOF_DOCKER
}


