#!/usr/bin/env bash

set -e
set -u

echoerr() { printf "%s\n" "$*" >&2; }

# Basic function to test that an http status code is 2x
http_status_code_ok() {
  if [ $1 -lt 200 -o $1 -gt 204 ]; then
    return 1
  else
    return 0
  fi
}

wait_for_docker_services_healthy() {
    #ignore non mandatory services (everything but remote-engine-client and remote-engine-agent)
    # so the process can start quicker
    # note that others services with a healthcheck will be monitoring by autoheal
    docker_compose_services=(`docker-compose ps --services | grep remote-engine`)
    docker_compose_services_length=${#docker_compose_services[@]}

    docker_compose_services_state=()
    for (( i=0; i<${docker_compose_services_length}; i++ ));
    do
      docker_compose_services_state[$i]=''
    done

    max_try=20
    count=0
    all_services_healthy=0

    while [[ ($count -lt $max_try) && ($all_services_healthy -lt $docker_compose_services_length) ]];
    do
      echo "Try ${count} - nb services healthy: ${all_services_healthy}"
      for (( i=0; i<${docker_compose_services_length}; i++ ));
      do
        service=${docker_compose_services[$i]}
        container_id=(`docker-compose ps -q ${service}`)
        container_healthy=(`docker inspect -f '{{ .State.Health.Status }}' ${container_id}`)
        echo "Service '${service}' state is '${container_healthy}'"

        if [[ ("${container_healthy}" == 'healthy') && ( "${docker_compose_services_state[$i]}" != 'healthy' ) ]]; then
          all_services_healthy=$(( all_services_healthy+1 ))
          echo "Nb containers healthy: ${all_services_healthy}"
        fi
        docker_compose_services_state[$i]=${container_healthy}
      done
      (( count++ ))
      sleep 5
    done

    if [[ ${all_services_healthy} != ${docker_compose_services_length} ]]; then
      echoerr "At least one docker service is unhealthy"
      return 1
    fi

    echo "${docker_compose_services_length} docker services are healthy"
    return 0

}

start() {

    if [[ -z "${TALEND_DIR:-}" ]]; then
         echoerr "Required TALEND_DIR variable is empty"
         exit 1
    fi


    if [[ -z "${PRE_AUTHORIZED_KEY:-}" ]]; then
         echoerr "Required PRE_AUTHORIZED_KEY variable is empty"
         exit 1
    fi

    if [[ ! -z "${PRE_AUTHORIZED_KEY:-}" && !( -f "${TALEND_DIR}/config.json") ]]; then
       echo ${PRE_AUTHORIZED_KEY} > "${TALEND_DIR}/pairkey"
    fi

    cd ${TALEND_DIR}
    echo "Launch Remote Engine for Pipelines services from $TALEND_DIR"
    if [[ ! $(grep 'registry' .env) ]]; then
      docker-compose pull
    fi
    docker-compose up -d

    # wait for the services to be healthy
    if ! wait_for_docker_services_healthy; then
      stop
      exit 1
    fi

    }

stop() {
    echo "Stop Remote Engine for Pipelines services"
    if [[ -z "${TALEND_DIR}" ]]; then
         echoerr "Required TALEND_DIR variable is empty"
         exit 1
    fi
    cd ${TALEND_DIR} && docker-compose down -v
}

restart() {
    stop
    start
}

case $1 in
  start|stop|restart) "$1" ;;
esac
