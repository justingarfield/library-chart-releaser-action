#!/usr/bin/env bash

# Copyright The Helm Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_RELEASER_VERSION=v1.4.1

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help               Display help
    -v, --version            The chart-releaser version to use (default: $DEFAULT_CHART_RELEASER_VERSION)"
        --config             The path to the chart-releaser config file
    -u, --charts-repo-url    The GitHub Pages URL to the charts repo (default: https://<owner>.github.io/<repo>)
    -o, --owner              The repo owner
    -r, --repo               The repo name
    -n, --install-dir        The Path to install the cr tool
    -i, --install-only       Just install the cr tool
EOF
}

main() {
    local version="$DEFAULT_CHART_RELEASER_VERSION"
    local config=
    local owner=
    local repo=
    local charts_repo_url=
    local install_dir=
    local install_only=

    parse_command_line "$@"

    : "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"

    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    pushd "$repo_root" > /dev/null

    # TODO: Need to spend a few minutes and determine if I want to look for chart changes or not, might be moot w/ single chart
    #echo 'Looking up latest tag...'
    #local latest_tag
    #latest_tag=$(lookup_latest_tag)

    #echo "Determining if the library chart changed since '$latest_tag'..."
    #local chart_changed=false
    #chart_changed=$(library_chart_changed "$latest_tag")

    install_chart_releaser

    rm -rf .cr-release-packages
    mkdir -p .cr-release-packages

    rm -rf .cr-index
    mkdir -p .cr-index

    package_library_chart

    upload_library_chart_package_to_github
    
    update_helm_repository_index_and_push

    popd > /dev/null
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            --config)
                if [[ -n "${2:-}" ]]; then
                    config="$2"
                    shift
                else
                    echo "ERROR: '--config' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -v|--version)
                if [[ -n "${2:-}" ]]; then
                    version="$2"
                    shift
                else
                    echo "ERROR: '-v|--version' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -u|--charts-repo-url)
                if [[ -n "${2:-}" ]]; then
                    charts_repo_url="$2"
                    shift
                else
                    echo "ERROR: '-u|--charts-repo-url' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -o|--owner)
                if [[ -n "${2:-}" ]]; then
                    owner="$2"
                    shift
                else
                    echo "ERROR: '--owner' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -r|--repo)
                if [[ -n "${2:-}" ]]; then
                    repo="$2"
                    shift
                else
                    echo "ERROR: '--repo' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -n|--install-dir)
                if [[ -n "${2:-}" ]]; then
                    install_dir="$2"
                    shift
                fi
                ;;
            -i|--install-only)
                if [[ -n "${2:-}" ]]; then
                    install_only="$2"
                    shift
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done

    if [[ -z "$owner" ]]; then
        echo "ERROR: '-o|--owner' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$repo" ]]; then
        echo "ERROR: '-r|--repo' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$charts_repo_url" ]]; then
        charts_repo_url="https://$owner.github.io/$repo"
    fi

    if [[ -z "$install_dir" ]]; then
        local arch
        arch=$(uname -m)
        install_dir="$RUNNER_TOOL_CACHE/cr/$version/$arch"
    fi

    if [[ -n "$install_only" ]]; then
        echo "Will install cr tool and not run it..."
        install_chart_releaser
        exit 0
    fi
}

install_chart_releaser() {
    if [[ ! -d "$RUNNER_TOOL_CACHE" ]]; then
        echo "Cache directory '$RUNNER_TOOL_CACHE' does not exist" >&2
        exit 1
    fi

    if [[ ! -d "$install_dir" ]]; then
        mkdir -p "$install_dir"

        echo "Installing chart-releaser on $install_dir..."
        curl -sSLo cr.tar.gz "https://github.com/helm/chart-releaser/releases/download/$version/chart-releaser_${version#v}_linux_amd64.tar.gz"
        tar -xzf cr.tar.gz -C "$install_dir"
        rm -f cr.tar.gz
    fi

    echo 'Adding cr directory to PATH...'
    export PATH="$install_dir:$PATH"
}

lookup_latest_tag() {
    git fetch --tags > /dev/null 2>&1

    if ! git describe --tags --abbrev=0 2> /dev/null; then
        git rev-list --max-parents=0 --first-parent HEAD
    fi
}

library_chart_changed() {
    local commit="$1"

    local changed_files
    changed_files=$(git diff --find-renames --name-only "$commit" -- ".")

    local depth=$(( $(tr "/" "\n" <<< "." | sed '/^\(\.\)*$/d' | wc -l) + 1 ))
    local fields="1-${depth}"

    cut -d '/' -f "$fields" <<< "$changed_files" | uniq | filter_charts
}

package_library_chart() {
    local args=()
    if [[ -n "$config" ]]; then
        args+=(--config "$config")
    fi

    echo "Packaging library chart..."
    cr package "${args[@]}"
}

upload_library_chart_package_to_github() {
    local args=(-o "$owner" -r "$repo" -c "$(git rev-parse HEAD)")
    if [[ -n "$config" ]]; then
        args+=(--config "$config")
    fi

    echo 'Releasing charts...'
    cr upload "${args[@]}"
}

update_helm_repository_index_and_push() {
    local SSH_REPO=false
    local PROJECT_USERNAME=""
    local PROJECT_REPONAME=""

    local args=(-o "$owner" -r "$repo" -c "$charts_repo_url" --push)
    if [[ -n "$config" ]]; then
        args+=(--config "$config")
    fi

    # For testing locally. chart-releaser utility does not currently support Git Repo access via SSH, only HTTPS.
    [[ $(git config --get remote.origin.url) == *"git@github.com"* ]] && \
    SSH_REPO=true && \
    PROJECT_USERNAME=$(git config --get remote.origin.url | sed 's/git\@github\.com\:\|\.git\|https\:\/\/github\.com\///g' | awk -F/ '{printf $1}') && \
    PROJECT_REPONAME=$(git config --get remote.origin.url | sed 's/git\@github\.com\:\|\.git\|https\:\/\/github\.com\///g' | awk -F/ '{printf $2}')

    [[ ${SSH_REPO} == *"true"* ]] && \
      git remote set-url origin https://github.com/"${PROJECT_USERNAME}"/"${PROJECT_REPONAME}"

    echo 'Updating charts repo index...'
    cr index "${args[@]}"

    [[ ${SSH_REPO} == *"true"* ]] && \
      git remote set-url origin git@github.com:"${PROJECT_USERNAME}"/"${PROJECT_REPONAME}".git
}

main "$@"
