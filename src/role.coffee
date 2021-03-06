import { guard } from "./helpers"

import {
  getSecretARN
  getWildcardARN
} from "@dashkite/dolores/secrets"

import { 
  createRole
} from "@dashkite/dolores/roles"

import {
  getLambdaARN
} from "@dashkite/dolores/lambda"

import {
  getStepFunctionARN
} from "@dashkite/dolores/step-function"

import {
  getBucketARN
} from "@dashkite/dolores/bucket"

import {
  getQueueARN
} from "@dashkite/dolores/queue"

buildCloudWatchPolicy = (name, handler) ->
  region = handler.region ? "us-east-1"

  Effect: "Allow"
  Action: [
    "logs:CreateLogGroup"
    "logs:CreateLogStream"
    "logs:PutLogEvents"
  ]
  Resource: [ 
    "arn:aws:logs:*:*:log-group:/aws/lambda/#{name}:*" 
    "arn:aws:logs:*:*:log-group:/aws/lambda/#{region}.#{name}:*" 
  ]

buildSecretsPolicy = (secrets) ->
  console.log "*** build secrets policy ***"

  Effect: "Allow"
  Action: [ "secretsmanager:GetSecretValue" ]
  Resource: await do ->
    for secret in secrets
      if secret.type == "wildcard"
        console.log "authorize secret access for wildcard scope: #{secret.name}"
        await getWildcardARN secret.name
      else
        console.log "authorize secret access for: #{secret.name}"
        await getSecretARN secret.name

mixinPolicyBuilders =

  graphite: (mixin, base) ->
    
    region = mixin.region ? "us-east-1"

    [
      Effect: "Allow"
      Action: [ "dynamodb:*" ]
      Resource: do ->
        resources = []
        for table in mixin.tables
          _table = "#{base}-#{table}"
          resources.push "arn:aws:dynamodb:#{region}:*:table/#{_table}"
          resources.push "arn:aws:dynamodb:#{region}:*:table/#{_table}/*"
        resources
    ]

  s3: (mixin, base) ->

    [
      Effect: "Allow"
      Action: [ "s3:*" ]
      Resource: do ->
        resources = []
        for bucket in mixin.buckets
          _bucket = "#{base}-#{bucket}"
          resources.push "arn:aws:s3:::#{_bucket}"
          resources.push "arn:aws:s3:::#{_bucket}/*"
        resources
    ]


  kms: (mixin, base) ->

    # TODO allow for use of keys
    # see also: https://github.com/pandastrike/sky-mixin-kms/blob/master/src/policy.coffee#L4-L26

    [

      Effect: "Allow"
      Action: [
        "kms:GenerateRandom"
      ]
      Resource: ["*"]

    ]

  lambda: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "lambda:InvokeFunction"
      ]
      Resource: [
        await getLambdaARN mixin.name
      ]

    ]

  "step-function": do (self = false, managed = null) ->
    managed = [
        Effect: "Allow"
        Action:[
          "events:PutTargets"
          "events:PutRule"
          "events:DescribeRule"
        ]
        Resource: [
          "arn:aws:events:us-east-1:618441030511:rule/StepFunctionsGetEventsForStepFunctionsExecutionRule"
        ]
      ,
        Effect: "Allow"
        Action:[
          "states:DescribeExecution"
          "states:StopExecution"
          "states:ListStateMachines"
        ]
        Resource: '*'
    ]

    (mixin) ->
      policies = [
        Effect: "Allow"
        Action: [ 
          "states:startExecution" 
        ]
        Resource: [ await getStepFunctionARN mixin.name ]      
      ]

      if self == false
        policies.push managed...
        self = true

      policies

  bucket: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "s3:GetObject"
        "s3:PutObject"
        "s3:DeleteObject"
      ]
      Resource: "#{ getBucketARN mixin.name }/*"

    ]

  queue: (mixin) ->
    [

      Effect: "Allow"
      Action: [
        "sqs:GetQueueUrl"
        "sqs:DeleteMessage"
        "sqs:ReceiveMessage"
        "sqs:SendMessage"
      ]
      Resource: await getQueueARN mixin.name

    ]
    

  

buildMixinPolicy = (mixin, base) ->
  if ( builder = mixinPolicyBuilders[ mixin.type ])?
    builder mixin, base
  else
    throw new Error "Unknown mixin [ #{mixin} ] for [ #{base} ]"

export default (genie, { namespace, lambda, mixins, secrets, buckets, queues }) ->

  # TODO add delete / teardown
  # TODO add support for multiple lambdas
  
  genie.define "sky:roles:publish", guard (environment) ->

    base = "#{namespace}-#{environment}"

    for handler in ( lambda?.handlers ? [] )

      lambda = "#{base}-#{handler.name}"
      role = "#{lambda}-role"

      # TODO possibly explore how to split out role building
      # TODO allow for different policies for different handlers
      policies = [ ( buildCloudWatchPolicy lambda, handler ) ]

      if secrets? && secrets.length > 0
        policies.push await buildSecretsPolicy secrets

      if buckets? && buckets.length > 0
        for bucket in buckets
          _bucket = { bucket..., type: "bucket" }
          policies.push ( await buildMixinPolicy _bucket, base )...

      if queues? && queues.length > 0
        for queue in queues
          _queue = { queue..., type: "queue" }
          policies.push ( await buildMixinPolicy _queue, base )...

      if mixins?
        for mixin in mixins
          policies.push ( await buildMixinPolicy mixin, base )...

      await createRole role, policies

  genie.define "sky:roles:delete", guard (environment) ->
    base = "#{namespace}-#{environment}"

    for handler in ( lambda?.handlers ? [] )
      lambda = "#{base}-#{handler.name}"
      role = lambda
      deleteRole role