import zip from "./zip"
import secrets from "./secrets"
import role from "./role"
import lambda from "./lambda"
import alb from "./alb"
import edge from "./edge"
import bridge from "./bridge"
import stepFunction from "./step-function"
import buckets from "./s3"
import queues from "./queue"

export default (genie) ->
  if (options = genie.get "sky")?
    zip genie, options
    secrets genie, options
    role genie, options
    lambda genie, options
    alb genie, options
    edge genie, options
    bridge genie, options
    stepFunction genie, options
    buckets genie, options
    queues genie, options
