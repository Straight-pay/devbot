HerokuDeployment = require('./deployment').Deployment

process.env.HUBOT_DEPLOY_EMIT_GITHUB_DEPLOYMENTS = "true"

module.exports = (robot) ->
  # This is what happens with a '/deploy' request is accepted.
  #
  # msg - The hubot message that triggered the deployment. msg.reply and msg.send post back immediately
  # deployment - The deployment captured from a chat interaction. You can modify it before it's passed on to the GitHub API.
  robot.on "github_deployment", (msg, deployment) ->
    branchName = deployment.ref
    serverEnv = deployment.env
    # Handle the difference between userIds and roomIds in hipchat
    user = robot.brain.userForId deployment.user
    vault = robot.vault.forUser(user)
    githubDeployToken = vault.get "hubot-deploy-github-secret"
    if githubDeployToken?
      deployment.setUserToken(githubDeployToken)
      
    if deployment.application.provider in [ "heroku", "capistrano" ]
      deployment.post (err, status, body, headers, responseMessage) =>
        dep = new HerokuDeployment(body, process.env.HEROKU_API_KEY, process.env.GITHUB_TOKEN, robot.logger)
        dep.run (err,res,body,reaper)->
          if res?
            robot.emit 'slack.attachment',
              content:
                color: "good"
                title: "Deploying to #{serverEnv}"
                title_link: "#{JSON.parse(body).target_url}"
                text: "==== Deployment of #{branchName} to #{serverEnv} complete! ===="
              channel: "#hubot-test-chat" # optional, defaults to message.room
              username: "devbot" # optional, defaults to robot.name
          else
            robot.emit 'slack.attachment',
              content:
                color: "warning"
                title: "Deploying to #{serverEnv}"
                text: "==== Deploying, #{branchName} to #{serverEnv} ===="
              channel: "#hubot-test-chat" # optional, defaults to message.room
              username: "devbot" # optional, defaults to robot.name
    else
      msg.send "Sorry, I can't deploy #{deployment.name}, the provider is unsupported"

  # Reply with the most recent deployments that the api is aware of
  #
  # msg - The hubot message that triggered the deployment. msg.reply and msg.send post back immediately
  # deployment - The deployed app that matched up with the request.
  # deployments - The list of the most recent deployments from the GitHub API.
  # formatter - A basic formatter for the deployments that should work everywhere even though it looks gross.
  robot.on "hubot_deploy_recent_deployments", (msg, deployment, deployments, formatter) ->
    msg.send formatter.message()

  # Reply with the environments that hubot-deploy knows about for a specific application.
  #
  # msg - The hubot message that triggered the deployment. msg.reply and msg.send post back immediately
  # deployment - The deployed app that matched up with the request.
  # formatter - A basic formatter for the deployments that should work everywhere even though it looks gross.
  robot.on "hubot_deploy_available_environments", (msg, deployment) ->
    msg.send "#{deployment.name} can be deployed to #{deployment.environments.join(', ')}."

  # An incoming webhook from GitHub for a deployment.
  #
  # deployment - A Deployment from github_events.coffee
  robot.on "github_deployment_event", (deployment) ->
    robot.logger.info JSON.stringify(deployment)

  # An incoming webhook from GitHub for a deployment status.
  #
  # status - A DeploymentStatus from github_events.coffee
  robot.on "github_deployment_status_event", (status) ->
    if status.notify
      user  = robot.brain.userForId status.notify.user
      status.actorName = user.name

    messageBody = status.toSimpleString().replace(/^hubot-deploy: /i, '')
    robot.logger.info messageBody
    if status?.notify?.room?
      robot.messageRoom status.notify.room, messageBody