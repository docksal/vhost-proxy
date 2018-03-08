#!/usr/bin/env bats

# Debugging
# TODO: looks like this only outputs the first line instead of all lines.
teardown() {
	echo "Status: $status"
	echo "Output:"
	echo "================================================================"
	for line in "${lines[@]}"; do
		echo $line
	done
	echo "================================================================"
}

# Global skip
# Uncomment below, then comment skip in the test you want to debug. When done, reverse.
#SKIP=1

@test "Proxy container is up and using the \"${IMAGE}\" image" {
	[[ ${SKIP} == 1 ]] && skip

	run fin docker ps --filter "name=docksal-vhost-proxy" --format "{{ .Image }}"
	[[ "$output" =~ "$IMAGE" ]]
	unset output
}

@test "Projects directory is mounted" {
	[[ ${SKIP} == 1 ]] && skip

	run fin docker exec docksal-vhost-proxy ls -la /projects
	[[ "$output" =~ "project1" ]]
	[[ "$output" =~ "project2" ]]
}

@test "Cron is working" {
	[[ ${SKIP} == 1 ]] && skip

	# 'proxyctl cron' should be invoked every minute
	sleep 60s

	run make logs
	echo "$output" | grep "[proxyctl] [cron]"
	unset output
}

@test "Test projects are up and running" {
	[[ ${SKIP} == 1 ]] && skip

	# TODO: figure out why fin aliases do not work on Travis
	fin @project1 restart
	fin @project2 restart

	run fin pl
	[[ "$output" =~ "project1" ]]
	[[ "$output" =~ "project2" ]]
}

@test "Proxy returns 404 for a non-existing virtual-host" {
	[[ ${SKIP} == 1 ]] && skip

	run curl -I http://nonsense.docksal
	[[ "$output" =~ "HTTP/1.1 404 Not Found" ]]
	unset output
}

@test "Proxy returns 200 for an existing virtual-host" {
	[[ ${SKIP} == 1 ]] && skip

	run curl -I http://project1.docksal
	[[ "$output" =~ "HTTP/1.1 200 OK" ]]
	unset output

	run curl -I http://project2.docksal
	[[ "$output" =~ "HTTP/1.1 200 OK" ]]
	unset output
}

# We have to use a different version of curl here built with http2 support
@test "Proxy uses HTTP/2 for HTTPS connections" {
	[[ ${SKIP} == 1 ]] && skip

	# Non-existing project
	run make curl -e ARGS='-kI https://nonsense.docksal'
	[[ "$output" =~ "HTTP/2 404" ]]
	unset output

	# Existing projects
	run make curl -e ARGS='-kI https://project1.docksal'
	[[ "$output" =~ "HTTP/2 200" ]]
	unset output

	run make curl -e ARGS='-kI https://project2.docksal'
	[[ "$output" =~ "HTTP/2 200" ]]
	unset output
}

@test "Proxy stops project containers after \"${PROJECT_INACTIVITY_TIMEOUT}\" of inactivity" {
	[[ ${SKIP} == 1 ]] && skip

	[[ "$PROJECT_INACTIVITY_TIMEOUT" == "0" ]] &&
		skip "Stopping has been disabled via PROJECT_INACTIVITY_TIMEOUT=0"

	# Restart projects to reset timing
	fin @project1 restart
	fin @project2 restart

	# Wait
	date
	sleep ${PROJECT_INACTIVITY_TIMEOUT}
	date

	fin docker exec docksal-vhost-proxy proxyctl stats
	# Trigger proxyctl stop manually to skip the cron job wait.
	# Note: cron job may still have already happened here and stopped the inactive projects
	fin docker exec docksal-vhost-proxy proxyctl stop

	# Check projects were stopped, but not removed
	run fin pl -a
	echo "$output" | grep project1 | grep 'Exited (0)'
	echo "$output" | grep project2 | grep 'Exited (0)'
	unset output

	# Check project networks were removed
	run fin docker network ls
	echo "$output" | grep -v project1
	echo "$output" | grep -v project2
	unset output
}

@test "Proxy starts an existing stopped project (HTTP)" {
	[[ ${SKIP} == 1 ]] && skip

	# Make sure the project is stopped
	fin @project1 stop

	run curl http://project1.docksal
	[[ "$output" =~ "Waking up the daemons..." ]]
	unset output

	run curl http://project1.docksal
	[[ "$output" =~ "Project 1" ]]
	unset output
}

@test "Proxy starts an existing stopped project (HTTPS)" {
	[[ ${SKIP} == 1 ]] && skip

	# Make sure the project is stopped
	fin @project1 stop

	run curl -k https://project1.docksal
	[[ "$output" =~ "Waking up the daemons..." ]]
	unset output

	run curl -k https://project1.docksal
	[[ "$output" =~ "Project 1" ]]
	unset output
}

@test "Proxy cleans up projects after \"${PROJECT_DANGLING_TIMEOUT}\" of inactivity" {
	[[ ${SKIP} == 1 ]] && skip

	[[ "$PROJECT_DANGLING_TIMEOUT" == "0" ]] &&
		skip "Cleanup has been disabled via PROJECT_DANGLING_TIMEOUT=0"

	# Make sure projects are stopped
	# Note: This is necessary to avoid log entries resulting from the cron job stopping projects, which would reset
	# the log timing, thus container may be considered active/not-dangling
	fin @project1 stop
	fin @project2 stop

	# Wait
	date
	sleep ${PROJECT_DANGLING_TIMEOUT}
	date

	fin docker exec docksal-vhost-proxy proxyctl stats
	# Trigger proxyctl cleanup manually to skip the cron job wait.
	fin docker exec docksal-vhost-proxy proxyctl cleanup

	# Check project1 containers were removed
	run fin docker ps -a -q --filter "label=com.docker.compose.project=project1"
	[[ "$output" == "" ]]
	unset output
	# Check project1 network was removed
	run fin docker network ls
	echo "$output" | grep -v project1
	unset output
	# Check project1 folder was removed
	fin docker exec docksal-vhost-proxy ls -la /projects
	echo "$output" | grep -v project1
}

@test "Proxy does not clean up permanent projects" {
	[[ ${SKIP} == 1 ]] && skip

	[[ "$PROJECT_DANGLING_TIMEOUT" == "0" ]] &&
		skip "Cleanup has been disabled via PROJECT_DANGLING_TIMEOUT=0"

	# Check that project2 still exist
	run fin pl -a
	echo "$output" | grep project2
	unset output
	# Check that project2 folder was NOT removed
	run fin docker exec docksal-vhost-proxy ls -la /projects
	echo "$output" | grep project2
	unset output
}
