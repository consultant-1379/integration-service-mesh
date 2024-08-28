pipelineJob('udm-5g-service-mesh-notify') {

    properties {
        disableConcurrentBuilds()
    }

    logRotator(-1, 15, 1, -1)

    authorization {
        permission('hudson.model.Item.Read', 'anonymous')
        permission('hudson.model.Item.Read:authenticated')
        permission('hudson.model.Item.Build:authenticated')
        permission('hudson.model.Item.Cancel:authenticated')
        permission('hudson.model.Item.Workspace:authenticated')
    }

    parameters {
        stringParam (
            'CHART_NAME',
            '',
            'Helm chart name part of requirements.yaml for eric-udm-mesh-integration'
        )
        stringParam (
            'CHART_VERSION',
            '',
            'Helm chart version'
        )
        stringParam (
            'GERRIT_BRANCH',
            'master',
            'Branch that will be used to clone Jenkinsfile from 5gcicd/integration-service-mesh repository'
        )
        stringParam (
            'GERRIT_REFSPEC',
            ' ',
            '''Refspec for 5gcicd/integration-service-mesh repository. This parameter takes prevalence over
            the CHART_* parameters. It will download the specified refspec to prepare a new version of
            eric-udm-mesh-integration helm chart.
            This parameter is also used to clone the Jenkinsfile that will run the job'''
        )
        stringParam (
            'PREPARE_RESULT',
            'FAIL',
            'This parameter control whether Gerrit vote will be -1/+1'
        )
        stringParam (
            'TESTS_RESULT',
            'FAIL',
            'This parameter and DEPLOY_RESULT control whether Gerrit vote will be -1/+1'
        )
        stringParam (
            'DEPLOY_RESULT',
            'FAIL',
            'This parameter and TESTS_RESULT control whether Gerrit vote will be -1/+1'
        )
        stringParam (
            'SPINNAKER_URL',
            '',
            'Url pointing to the spinnaker pipeline being executed'
        )
         stringParam (
            'EMAIL_NOTIFY',
            '',
            'Comma separated values of email address to recieve notification.'
        )
        stringParam (
            'JENKINS_GERRIT_BRANCH',
            'master',
            'Branch that will be used to clone Jenkinsfile from 5gcicd/integration-service-mesh repository'
        )
        stringParam (
            'JENKINS_GERRIT_REFSPEC',
            '${GERRIT_REFSPEC}',
            '''Refspec for 5gcicd/integration-service-mesh repository. This parameter takes prevalence over
            the CHART_* parameters. It will download the specified refspec to prepare a new version of
            eric-udm-mesh-integration helm chart.
            This parameter is also used to clone the Jenkinsfile that will run the job'''
        )
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        name('origin')
                        url('https://${COMMON_GERRIT_URL}/a/5gcicd/integration-service-mesh')
                        credentials('userpwd-adp')
                        refspec('${JENKINS_GERRIT_REFSPEC}')
                    }
                    branch('${JENKINS_GERRIT_BRANCH}')
                    extensions {
                        wipeOutWorkspace()
                        choosingStrategy {
                            gerritTrigger()
                        }
                    }
                }
                scriptPath('cicd/Jenkinsfile.notify')
            }
        }
    }
}
