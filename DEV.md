# SDK Developer Guide

This guide targets Developers of this SDK. It explains how to build the project and how the CI setup works.

## <a name="sample-app" /> How to Build the Sample App

First, you must setup some environment variables which are required by the project.

```
RMAAPIEndpoint=https://www.example.com
RASApplicationIdentifier=test-app-id
RASProjectSubscriptionKey=test-subscription-key
```

Next, run `pod install` from the root directory, open `MiniApp.xcworkspace`, and you should be able to successfully build the Sample App.

*Note:* You must define the environment variables before installing the pods because there is a post install script which sets up the project with your environment variables.

## How to Test with the Sample App

We currently don't provide an API for public use, so you must provide your own API.

## Continuous Integration and Deployment

[TravisCI](https://travis-ci.org/github/rakutentech/ios-miniapp) is used for building and testing the project for every pull request. It is also used for publishing the SDK and Sample App.

Note that two Sample App builds are created on merge to master or during a release: 
- One build for the iOS Simulator (built on TravisCI and then uploaded to App Center - App Center does not support building for the Simulator target)
- One build for iOS Devices (built directly on App Center in order to keep the certificate and provisioning profile secret)

### Merge to Master

The following describes the steps that CI performs when a branch is merged to master.

1. We trigger a build on TravisCI by merging a branch to master.
2. CI builds SDK and Sample App, run tests, linting, etc.
3. CI creates a ZIP file for the iOS Simulator (Staging) build of the Sample App.
    - Publishes build to App Center "Testers" group.
4. App Center builds the Sample App for iOS Devices (Staging).
    - Publishes build to App Center "Testers" group.

### Release

The following describes the steps that CI performs when releasing a new version of the SDK.

1. We trigger a build on TravisCI by pushing a Git tag to the repo in the format `vX.X.X`.
2. CI builds SDK and Sample App, run tests, linting, etc.
3. CI publishes the SDK to [Cocoapods](https://cocoapods.org/pods/MiniApp).
4. CI creates ZIP file for the iOS Simulator (Production) build of the Sample App.
    - Publishes build to App Center "Production" group.
5. CI merges the `master` branch into the `prod` branch.
    - This triggers a build on App Center for the iOS Device (Production) build of the Sample App.
    - Publishes build to App Center "Production" group.
6. CI publishes documentation to [Github Pages site](https://rakutentech.github.io/ios-miniapp).
