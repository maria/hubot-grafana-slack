# Description:
#   Share Grafana dashboards in Slack, privately
#
#   Examples:
#   - `hubot grafana get graphite-carbon-metrics` - Get all panels in the dashboard
#   - `hubot grafana get graphite-carbon-metrics:3` - Get only the third panel, from left to right, of a particular dashboard
#   - `hubot grafana get graphite-carbon-metrics:panel-8` - Get only the panel of a particular dashboard with the ID of 8
#   - `hubot grafana get graphite-carbon-metrics:cpu` - Get only the panels containing "cpu" (case insensitive) in the title
#   - `hubot grafana get graphite-carbon-metrics now-12hr` - Get a dashboard with a window of 12 hours ago to now
#   - `hubot grafana get graphite-carbon-metrics now-24hr now-12hr` - Get a dashboard with a window of 24 hours ago to 12 hours ago
#   - `hubot grafana get graphite-carbon-metrics:3 now-8d now-1d` - Get only the third panel of a particular dashboard with a window of 8 days ago to yesterday
#
# Configuration:
#   HUBOT_GRAFANA_HOST - Host for your Grafana 2.0 install, e.g. 'http://play.grafana.org'
#   HUBOT_GRAFANA_API_KEY - API key for a particular user (leave unset if unauthenticated)
#   HUBOT_GRAFANA_QUERY_TIME_RANGE - Optional; Default time range for queries (defaults to 6h)
#
# Dependencies:
#   "request": "~2"
#
# Commands:
#   hubot grafana get <dashboard slug>[:<panel id>][ <template variables>][ <from clause>][ <to clause>] - Show grafana dashboard graphs
#   hubot grafana list <tag> - Lists all dashboards available (optional: <tag>)
#   hubot grafana search <keyword> - Search available dashboards by <keyword>
#

crypto      = require 'crypto'
fs          = require 'fs'
request     = require 'request'
slackClient = require '@slack/client'


module.exports = (robot) ->
  # Various configuration options stored in environment variables
  grafana_host = process.env.HUBOT_GRAFANA_HOST
  grafana_api_key = process.env.HUBOT_GRAFANA_API_KEY
  grafana_query_time_range = process.env.HUBOT_GRAFANA_QUERY_TIME_RANGE or '1h'
  slack_token = process.env.HUBOT_SLACK_TOKEN

  # Get a specific dashboard with options
  robot.respond /(?:grafana|graf) (?:dash|dashboard|get) ([A-Za-z0-9\-\:_]+)(.*)?/i, (msg) ->

    slug = msg.match[1].trim()
    remainder = msg.match[2]
    timespan = {
      from: "now-#{grafana_query_time_range}"
      to: 'now'
    }
    variables = ''
    template_params = []
    visualPanelId = false
    apiPanelId = false
    pname = false

    # Parse out a specific panel
    if /\:/.test slug
      parts = slug.split(':')
      slug = parts[0]
      visualPanelId = parseInt parts[1], 10
      if isNaN visualPanelId
        visualPanelId = false
        pname = parts[1].toLowerCase()
      if /panel-[0-9]+/.test pname
        parts = pname.split('panel-')
        apiPanelId = parseInt parts[1], 10
        pname = false

    # Check if we have any extra fields
    if remainder
      # The order we apply non-variables in
      timeFields = ['from', 'to']

      for part in remainder.trim().split ' '
        # Check if it's a variable or part of the timespan
        if part.indexOf('=') >= 0
          variables = "#{variables}&var-#{part}"
          template_params.push { "name": part.split('=')[0], "value": part.split('=')[1] }

        # Only add to the timespan if we haven't already filled out from and to
        else if timeFields.length > 0
          timespan[timeFields.shift()] = part.trim()

    robot.logger.debug msg.match
    robot.logger.debug slug
    robot.logger.debug timespan
    robot.logger.debug variables
    robot.logger.debug template_params
    robot.logger.debug visualPanelId
    robot.logger.debug apiPanelId
    robot.logger.debug pname

    # Call the API to get information about this dashboard
    callGrafana "dashboards/db/#{slug}", (dashboard) ->
      robot.logger.debug dashboard

      # Check dashboard information
      if !dashboard
        return sendError 'An error ocurred. Check your logs for more details.', msg
      if dashboard.message
        return sendError dashboard.message, msg

      # Handle refactor done for version 2.0.2+
      if dashboard.dashboard
        # 2.0.2+: Changed in https://github.com/grafana/grafana/commit/e5c11691203fe68958e66693e429f6f5a3c77200
        data = dashboard.dashboard
        # The URL was changed in https://github.com/grafana/grafana/commit/35cc0a1cc0bca453ce789056f6fbd2fcb13f74cb
        apiEndpoint = 'dashboard-solo'
      else
        # 2.0.2 and older
        data = dashboard.model
        apiEndpoint = 'dashboard/solo'

      # Support for templated dashboards
      robot.logger.debug data.templating.list
      if data.templating.list
        template_map = []
        for template in data.templating.list
          robot.logger.debug template
          continue unless template.current
          for _param in template_params
            if template.name == _param.name
              template_map['$' + template.name] = _param.value
            else
              template_map['$' + template.name] = template.current.text

      # Return dashboard rows
      panelNumber = 0
      for row in data.rows
        for panel in row.panels
          robot.logger.debug panel

          panelNumber += 1

          # Skip if visual panel ID was specified and didn't match
          if visualPanelId && visualPanelId != panelNumber
            continue

          # Skip if API panel ID was specified and didn't match
          if apiPanelId && apiPanelId != panel.id
            continue

          # Skip if panel name was specified any didn't match
          if pname && panel.title.toLowerCase().indexOf(pname) is -1
            continue

          # Build links for message sending
          title = formatTitleWithTemplate(panel.title, template_map)
          imageUrl = "#{grafana_host}/render/#{apiEndpoint}/db/#{slug}/?panelId=#{panel.id}&width=1000&height=500&from=#{timespan.from}&to=#{timespan.to}#{variables}"

          fetchAndUpload msg, title, imageUrl

  # Get a list of available dashboards
  robot.respond /(?:grafana|graf) list\s?(.+)?/i, (msg) ->
    if msg.match[1]
      tag = msg.match[1].trim()
      callGrafana "search?tag=#{tag}", (dashboards) ->
        robot.logger.debug dashboards
        response = "Dashboards tagged `#{tag}`:\n"
        sendDashboardList dashboards, response, msg
    else
      callGrafana 'search', (dashboards) ->
        robot.logger.debug dashboards
        response = "Available dashboards:\n"
        sendDashboardList dashboards, response, msg

  # Search dashboards
  robot.respond /(?:grafana|graf) search (.+)/i, (msg) ->
    query = msg.match[1].trim()
    robot.logger.debug query
    callGrafana "search?query=#{query}", (dashboards) ->
      robot.logger.debug dashboards
      response = "Dashboards matching `#{query}`:\n"
      sendDashboardList dashboards, response, msg

  # Send Dashboard list
  sendDashboardList = (dashboards, response, msg) ->
    # Handle refactor done for version 2.0.2+
    if dashboards.dashboards
      list = dashboards.dashboards
    else
      list = dashboards

    robot.logger.debug list
    unless list.length > 0
      return

    for dashboard in list
      # Handle refactor done for version 2.0.2+
      if dashboard.uri
        slug = dashboard.uri.replace /^db\//, ''
      else
        slug = dashboard.slug
      response = response + "- #{slug}: #{dashboard.title}\n"

    # Remove trailing newline
    response.trim()

    msg.send response

  # Handle generic errors
  sendError = (message, msg) ->
    robot.logger.error message
    msg.send message

  # Format the title with template vars
  formatTitleWithTemplate = (title, template_map) ->
    title.replace /\$\w+/g, (match) ->
      if template_map[match]
        return template_map[match]
      else
        return match

  # Call off to Grafana
  callGrafana = (url, callback) ->
    if grafana_api_key
      authHeader = {
        'Accept': 'application/json',
        'Authorization': "Bearer #{grafana_api_key}"
      }
    else
      authHeader = {
        'Accept': 'application/json'
      }
    console.log("Get Grafana data: #{grafana_host}/api/#{url}")
    robot.http("#{grafana_host}/api/#{url}").headers(authHeader).get() (err, res, body) ->
      if (err)
        robot.logger.error err
        return callback(false)
      data = JSON.parse(body)
      return callback(data)

  # Fetch an image from provided URL, upload it to Slack
  fetchAndUpload = (msg, title, url) ->
    if grafana_api_key
        requestHeaders =
          encoding: null,
          auth:
            bearer: grafana_api_key
      else
        requestHeaders =
          encoding: null

    filePath = "/tmp/#{title}"

    request url, requestHeaders, (err, res, body) ->
      robot.logger.debug "Save files to local before uploading..."
      writeFile = fs.createWriteStream(filePath)
      writeFile.write(body)
      writeFile.end()

      robot.logger.debug "Upload #{filePath} to Slack..."
      uploadToSlack(msg, title, filePath)

      robot.logger.debug "Remove saved files for upload."
      fs.unlink(filePath)

  # Upload image to Slack
  uploadToSlack = (msg, title, filePath) ->
    slackChannels = msg.message.room || msg.user.name || '#general'

    slack = new slackClient.WebClient(slack_token)

    opts = {
      title: title,
      channels: slackChannels,
      file: fs.createReadStream(filePath)
    }

    slack.files.upload title, opts, (err, res) ->
      if err
        robot.logger.error "Upload Error Code: #{err}"
        msg.send "#{title} - [Upload Error] with options #{opts}"
      else
        robot.logger.debug "Image uploaded with options: #{opts}"
