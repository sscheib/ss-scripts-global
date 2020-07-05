#!/bin/bash
GIT_SSH_COMMAND="ssh -i /root/.ssh/bitbucket_read_only" git remote update &> /dev/null
while read -r line; do
  [[ "${line}" =~ Your[[:space:]]branch[[:space:]]is[[:space:]]up[[:space:]]to[[:space:]]date[[:space:]]with[[:space:]]\'origin\/master\'\.  ]] || {
    continue;
  };

  echo "0" && exit 0;
done < <(git status -uno)
echo "1" && exit 1;
