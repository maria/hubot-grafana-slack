# Grafana in Slack via Hubot

   **Share Grafana dashboards in Slack, privately**
   
Get Grafana dashboards in Slack, by directly uploading the dashboards to Slack.

## How to use

  - `hubot grafana get graphite-carbon-metrics` - Get all panels in the dashboard
  - `hubot grafana get graphite-carbon-metrics:3` - Get only the third panel, from left to right, of a particular dashboard
  - `hubot grafana get graphite-carbon-metrics:panel-8` - Get only the panel of a particular dashboard with the ID of 8
  - `hubot grafana get graphite-carbon-metrics:cpu` - Get only the panels containing "cpu" (case insensitive) in the title
  - `hubot grafana get graphite-carbon-metrics now-12hr` - Get a dashboard with a window of 12 hours ago to now
  - `hubot grafana get graphite-carbon-metrics now-24hr now-12hr` - Get a dashboard with a window of 24 hours ago to 12 hours ago
  - `hubot grafana get graphite-carbon-metrics:3 now-8d now-1d` - Get only the third panel of a particular dashboard with a window of 8 days ago to yesterday

## Configuration
 
 - You need to install Hubot as a Slack app and configure a new integration with it.
 - Add `hubot-grafana-slack` as a dependency in your Hubot *package.json* file,
  and append it in *external-scripts.json* file

 - Set the following environment variables:
    - HUBOT_SLACK_TOKEN (required) - Slack Hubot token
    - HUBOT_GRAFANA_HOST (required) - Host for your Grafana 2.0 install, e.g. 'http://play.grafana.org'
    - HUBOT_GRAFANA_API_KEY (optional) - API key for a particular user (leave unset if unauthenticated)
    - HUBOT_GRAFANA_QUERY_TIME_RANGE (optional) - Default time range for queries (defaults to 1h)

 - Start your Hubot instance with `--adapter slack`

## Commands
 
 ```
   @hubot grafana get <dashboard slug>[:<panel id>][ <template variables>][ <from clause>][ <to clause>] - Show grafana dashboard graphs
   @hubot grafana list <tag> - Lists all dashboards available (optional: <tag>)
   @hubot grafana search <keyword> - Search available dashboards by <keyword>
```

--- 
Based on [hubot-grafana](https://github.com/stephenyeargin/hubot-grafana), only 
that the graphs are uploaded directly to Slack, not via S3.
