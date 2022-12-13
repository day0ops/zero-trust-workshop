package gloo.authz

import future.keywords

import input.http_request as http_request
import input.check_request.attributes.request.http as envoy_request
import input.state.jwt as jwt_token

default allow := false

allow if {
	is_token_valid
	action_allowed
}

is_token_valid if {
	now := time.now_ns() / 1000000000
	now < token_payload.exp
}

action_allowed if {
	http_request.method == "GET"
	token_payload.groups[0] == "operators"
}

token_payload := payload {
    [_, payload, _] := io.jwt.decode(jwt_token)
}