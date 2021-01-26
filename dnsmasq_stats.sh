#!/bin/bash

declare __DNSMASQ_STATS=""
function dnsmasq_stats::get_dnsmasq_stats () {
  declare -r dnsmasqPid="$(pgrep dnsmasq)"
echo $dnsmasqPid
  [[ "${dnsmasqPid}" =~ ^[[:digit:]]+$ ]] || {
    return 1;
  };

  # as the logging within openwrt is not guaranteed to be in sync with the clock (hour wise)
  # the hours are only matched on two digits ([[:digit:]]{2}
  declare -r currentTimeRegex="$(date +'%Y-%m-%d [[:digit:]]{2}:%M:%S')"

  # notify dnsmasq to dump stats
  kill -USR1 "${dnsmasqPid}" || {
    return 2;
  };

  __DNSMASQ_STATS="$(tail -n 1000 /logs/dnsmasq.log | grep -E "^${currentTimeRegex}" | cut -d " " -f 6-)"
  # ^ gets the last 1000 lines of the dnsmasq log and uses the regex defined above to filter out irrelevant content
  # > additionally only fields starting from the 6th will be printed

} #; get_dnsmasq_stats ( )

function dnsmasq_stats::low_level_discovery {
  # lets first collect the servers
  declare -A servers
  while read -r line; do
    [[ "${line}" =~ ^server.([[:digit:]\.\#]+):.queries.sent.([[:digit:]]+),.retried.or.failed.([[:digit:]]+) ]] || {
      continue;
    };
    servers["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]},${BASH_REMATCH[3]}"
  done < <(echo "${__DNSMASQ_STATS}")

  # and generate the json data for low level discovery
  output='{ "data": ['
  for server in "${!servers[@]}"; do
    # for every server we have we add this to our output
    output+=" { \"{#SERVERADDRESS}\": \"${server}\",\"{#QUERIESSENT}\": \"-1\",\"{#QUERIESRETRIEDFAILED}\": \"-1\"},"
  done
  # we need to remove the trailing , and the prefixed spaces
  output="$(echo "${output}" | sed -e 's/,$//' -e 's/^ //g')"

  # finally we need to suffix this
  output+="]}"
  printf "${output}\n" | jq . || {
    echo "ERR"
  };
} #;

function dnsmasq_stats::parse_values {
  declare -i cacheSize=0
  declare -i queriesForwarded=0
  declare -i queriesLocallyAnswered=0
  declare -A servers
  while read -r line; do
    if [[ "${line}" =~ ^cache.size.([[:digit:]]+) ]]; then
      cacheSize="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^queries.forwarded.([[:digit:]]+),.queries.answered.locally.([[:digit:]]+) ]]; then
      queriesForwarded="${BASH_REMATCH[1]}"
      queriesLocallyAnswered="${BASH_REMATCH[2]}"
    elif [[ "${line}" =~ ^server.([[:digit:]\.\#]+):.queries.sent.([[:digit:]]+),.retried.or.failed.([[:digit:]]+) ]]; then
      servers["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]},${BASH_REMATCH[3]}"
    fi
  done < <(echo "${__DNSMASQ_STATS}")

  echo "- dnsmasq[cache,size] ${cacheSize}" | zabbix_sender -vv -i - -c /etc/zabbix_agentd.conf
  echo "- dnsmasq[queries,forwarded] ${queriesForwarded}" | zabbix_sender -vv -i - -c /etc/zabbix_agentd.conf
  echo "- dnsmasq[queries,locally_answered] ${queriesLocallyAnswered}" | zabbix_sender -vv -i - -c /etc/zabbix_agentd.conf

  for server in "${!servers[@]}"; do
    IFS="," read -ra queries <<<"${servers["${server}"]}"

    # check for the correct amount of indices
    [[ "${#queries[@]}" -eq 2 ]] || {
      echo "ERROR: SIZE";
      continue;
    };

    queriesSent="${queries[0]}"
    queriesRetriedOrFailed="${queries[1]}"
    echo "- dnsmasq["${server}",queries_sent] ${queriesSent}" | zabbix_sender -vv -i - -c /etc/zabbix_agentd.conf
    echo "- dnsmasq["${server}",queries_retried_or_failed] ${queriesRetriedOrFailed}" | zabbix_sender -vv -i - -c /etc/zabbix_agentd.conf
  done
} #;

# time 1595093575
#cache size 150, 0/650 cache insertions re-used unexpired cache entries.
#queries forwarded 217, queries answered locally 893
#pool memory in use 0, max 0, allocated 0
#server 10.0.1.1#53: queries sent 1, retried or failed 0
#server 10.10.51.1#53: queries sent 0, retried or failed 0
#server 10.10.20.1#53: queries sent 0, retried or failed 0
#server 10.1.1.1#53: queries sent 216, retried or failed 0
#server 10.10.30.3#53: queries sent 0, retried or failed 0
#server 10.10.10.3#53: queries sent 0, retried or failed 0


dnsmasq_stats::get_dnsmasq_stats || {
  echo "ERR: $?"
};

if [[ "${1}" =~ ^lowLevelDiscovery$ ]]; then
  dnsmasq_stats::low_level_discovery
else
  dnsmasq_stats::parse_values
fi
