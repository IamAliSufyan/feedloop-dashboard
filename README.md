# Feedloop dashboard (hosted shell)

Static, serverless review dashboard for Unloop's Feedloop content pipeline.
Contains NO content or secrets: everything is loaded client-side from the
private `unloop-app` repo via the GitHub API, using a fine-grained token you
paste once per device (stored in localStorage only).

Live: https://iamalisufyan.github.io/feedloop-dashboard/

Actions (approve / reject / edit / restore / Publish-ASAP flag) are committed
straight to the content branch; Claude's publisher picks them up from git.
Source of truth for the pipeline itself: `unloop-app/docs/marketing/feedloop/`.
