pipelineJob('udm-5g-service-mesh-trigger') {

    properties {
        disableConcurrentBuilds()
        pipelineTriggers {
            triggers {
                gerrit {
                    gerritProjects {
                        gerritProject {
                            disableStrictForbiddenFileVerification(false)
                            compareType('PLAIN')
                            pattern('5gcicd/integration-service-mesh')
                            branches {
                                branch {
                                    compareType('ANT')
                                    pattern('**')
                                }
                            }
                        }
                    }
                    gerritBuildSuccessfulCodeReviewValue(0)
                    gerritBuildSuccessfulVerifiedValue(0)
                    serverName('adp')
                    commentTextParameterMode('PLAIN')
                    triggerOnEvents {
                        commentAddedContains {
                            commentAddedCommentContains('(?<!-)verify-service-mesh')
                        }
                        commentAddedContains {
                            commentAddedCommentContains('(?<!-)publish-service-mesh')
                        }
                    }
                }
            }
        }
    }

    logRotator(-1, 15, 1, -1)

    authorization {
        permission('hudson.model.Item.Read', 'anonymous')
        permission('hudson.model.Item.Read:authenticated')
        permission('hudson.model.Item.Build:authenticated')
        permission('hudson.model.Item.Cancel:authenticated')
        permission('hudson.model.Item.Workspace:authenticated')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        name('origin')
                        url('https://${COMMON_GERRIT_URL}/a/5gcicd/integration-service-mesh')
                        credentials('userpwd-adp')
                        refspec('${GERRIT_REFSPEC}')
                    }
                    branch('${GERRIT_BRANCH}')
                    extensions {
                        wipeOutWorkspace()
                        choosingStrategy {
                            gerritTrigger()
                        }
                    }
                }
                scriptPath('cicd/Jenkinsfile.trigger')
            }
        }
    }
}
