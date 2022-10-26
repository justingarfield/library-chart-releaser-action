# library-chart-releaser-action

A GitHub Action that turns a Helm Library Chart repository into a self-hosted Helm Chart Repository using GitHub Pages.

## Differences from official chart-releaser-action

[chart-releaser-action](https://github.com/helm/chart-releaser) expects multiple charts, under a `charts/` directory in-order to function properly out-of-the-box. In the case of my library chart, and for singular charts, it just doesn't quite fit-the-bill. To get around this issue, I simply took the [chart-releaser-action](https://github.com/helm/chart-releaser) and modified it a bit to support a single, stand-alone, chart library / chart.

I've also added some code in the bash script to automatically switch the _origin_ from **SSH** to **HTTPS** before trying to run the `index` command for [chart-releaser](https://github.com/helm/chart-releaser). Unfortunately this command is hard-coded to manipulate HTTPS endpoints, and will throw errors if you're using SSH to communicate with your repository. After it's done with the `index` command, it will automatically set the origin back to **SSH** (if needed).

## Usage

### Pre-requisites

1. A GitHub repo containing a stand-alone Helm chart in the root of the repository.
1. A GitHub branch called `gh-pages` to store the published charts. See `charts_repo_url` for alternatives.
1. In your repo, go to Settings/Pages. Change the `Source` `Branch` to `gh-pages`.
1. Create a workflow `.yml` file in your `.github/workflows` directory. An [example workflow](#example-workflow) is available below.
  For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file)

### Inputs

- `version`: The chart-releaser version to use (default: v1.4.1)
- `config`: Optional config file for chart-releaser. For more information on the config file, see the [documentation](https://github.com/helm/chart-releaser#config-file)
- `charts_repo_url`: The GitHub Pages URL to the charts repo (default: `https://<owner>.github.io/<project>`)

### Environment variables

- `CR_TOKEN` (required): The GitHub token of this repository (`${{ secrets.GITHUB_TOKEN }}`)

For more information on environment variables, see the [documentation](https://github.com/helm/chart-releaser#environment-variables).

### Example Workflow

Create a workflow (eg: `.github/workflows/release-library-chart.yaml`):

```yaml
name: Release Library Chart

on:
  push:
    branches:
      - main

jobs:
  release:
    # depending on default permission settings for your org (contents being read-only or read-write for workloads), you will have to add permissions
    # see: https://docs.github.com/en/actions/security-guides/automatic-token-authentication#modifying-the-permissions-for-the-github_token
    permissions:
      contents: write
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Configure Git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
          git config init.defaultBranch main

      - name: Install Helm
        uses: azure/setup-helm@v3
        with:
          version: v3.10.0

      - name: Run library-chart-releaser
        uses: justingarfield/library-chart-releaser-action@v0.1.17
        env:
          CR_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
```

This uses [@justingarfield/library-chart-releaser-action](https://www.github.com/justingarfield/library-chart-releaser-action) to turn your GitHub repository into a self-hosted Helm chart repository.

#### Example using custom config

`release-library-chart.yml`:

```yaml
- name: Run library-chart-releaser
  uses: justingarfield/library-chart-releaser-action@v0.1.17
  with:
    config: cr.yaml
    charts_repo_url: xxxxxx
  env:
    CR_TOKEN: "${{ secrets.GITHUB_TOKEN }}"
```

`cr.yaml`:

```yaml
owner: myaccount
git-base-url: https://api.github.com/
```

For options see [config-file](https://github.com/helm/chart-releaser#config-file).

## Credit

A huge thanks to the [helm](https://github.com/helm) community for an awesome starting foundation and influencing the creation of this GitHub Action.

## Disclaimers

I do not offer any assistance or support for others that decide to clone / fork source from this repository. I'm providing this publicly as a way to share thoughts and ideas around how folks can work with Helm, based-upon what I'm actively consuming for my own home use. I work on Linux and Windows environments exclusively, so this project will not contain files or support for macOS.
