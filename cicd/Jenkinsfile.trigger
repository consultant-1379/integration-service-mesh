node("default-jenkins-slave") {
    stage('Write artifacts') {

        def ALWAYS_RELEASE = "False"
        def PUBLISH = "False"
        def VERIFY = "False"
        def VERSION_STRATEGY = "PATCH"

        def _gerrit_comment = env.GERRIT_EVENT_COMMENT_TEXT.toString().toLowerCase()
 
        if ( env.GERRIT_REFSPEC != "master" && env.GERRIT_EVENT_TYPE != null) {

            if (_gerrit_comment.contains("minor-version-strategy")) {
                VERSION_STRATEGY = "MINOR"
            }
             if (_gerrit_comment.contains("major-version-strategy")) {
                VERSION_STRATEGY = "MAJOR"
            }
            if (_gerrit_comment.contains("publish-service-mesh+1")) {
                PUBLISH = "True"
            }
            if (_gerrit_comment.contains("verify-service-mesh+1")) {
                VERIFY = "True"
            }
            if (_gerrit_comment.contains("is-release-version+1")) {
                ALWAYS_RELEASE = "True"
            }

            writeFile(file: 'artifact.properties', text:
                "CHART_NAME=\n" +
                "CHART_VERSION=\n" +
                "CHART_REPO=\n" +
                "GERRIT_REFSPEC=${env.GERRIT_REFSPEC}\n" +
                "GERRIT_EVENT_TYPE=${env.GERRIT_EVENT_TYPE}\n" +
                "GERRIT_PATCHSET_REVISION=${params.GERRIT_PATCHSET_REVISION}\n" +
                "GERRIT_BRANCH=${params.GERRIT_BRANCH}\n" +
                "ALWAYS_RELEASE=${ALWAYS_RELEASE.toString()}\n" +
                "VERIFY=${VERIFY.toString()}\n" +
                "VERSION_STRATEGY=${VERSION_STRATEGY.toString()}\n" +
                "PUBLISH=${PUBLISH.toString()}\n"
            )

            archiveArtifacts allowEmptyArchive: true, artifacts: 'artifact.properties', onlyIfSuccessful: true
        }
    }
}
