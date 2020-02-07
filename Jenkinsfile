import hudson.AbortException
import org.jenkinsci.plugins.workflow.steps.FlowInterruptedException

/* Tests will be run on these systems.
 * To add a new sytem simple extend this list.
 */
def systems = [
  'fedora28',
  'fedora29',
  'fedora30',
  'fedora31',
  'fedora-rawhide',
  'rhel7',
  'debian10',
]

/* Send notifications to Github.
 * If it is an on-demand run then no notifications are sent.
 */
class Notification {
  def pipeline
  String context
  String details_url
  String aws_url
  boolean on_demand

  /* @param pipeline Jenkins pipeline context.
   * @param context Github notification context (the bold text).
   * @param details_url Link for "details" button.
   * @param aws_url Link to cloud where logs are stored.
   * @param on_demand True if this is an on-demand run.
   *
   * There are two types of notifications:
   * a) Summary (i.e. sssd-ci: Success. details: @details_url)
   * b) Single build (i.e. sssd-ci/fedora28: Success. details: @aws_url)
   */
  Notification(pipeline, context, details_url, aws_url, on_demand) {
    this.pipeline = pipeline
    this.context = context
    this.details_url = details_url
    this.aws_url = aws_url
    this.on_demand = on_demand
  }

  /* Send notification. If system is not null single build is notified. */
  def notify(status, message, system = null) {
    def context = system ? "${this.context}/${system}" : this.context
    this.pipeline.echo "[${context}] ${status}: ${message}"

    if (this.on_demand) {
      return
    }

    this.send(status, message, context, this.getTargetURL(system))
  }

  private def send(status, message, context, url) {
    // A token need to be created for the repository with the needed
    // permissions to allow the notifications works.
    // Use that token as password for the credentials used to access
    // to the GitHub repository.
    this.pipeline.githubNotify status: status,
      context: context,
      description: message,
      targetUrl: url
  }

  private def getTargetURL(system) {
    if (system) {
      return String.format(
        '%s/%s/%s/%s/index.html',
        this.aws_url,
        this.pipeline.env.BRANCH_NAME,
        this.pipeline.env.BUILD_ID,
        system
      )
    }

    return this.details_url
  }
}

/* Manage test run. */
class Test {
  def pipeline
  String system
  Notification notification

  String artifactsdir
  String basedir
  String codedir
  String target

  /* @param pipeline Jenkins pipeline context.
   * @param system System to test on.
   * @param notification Notification object.
   */
  Test(pipeline, system, notification) {
    this.pipeline = pipeline
    this.system = system
    this.notification = notification

    this.basedir = "/home/fedora"
    this.target = pipeline.env.CHANGE_TARGET
  }

  /* Test entry point. */
  def run() {
    /* These needs to be set here in order to get correct workspace. */
    this.artifactsdir = "${this.pipeline.env.WORKSPACE}/artifacts/${this.system}"
    this.codedir = "${this.pipeline.env.WORKSPACE}/sssd"

    /* Clean-up previous artifacts just to be sure there are no leftovers. */
    this.pipeline.sh "rm -fr ${this.artifactsdir} || :"

    try {
      this.pipeline.echo "Running on ${this.pipeline.env.NODE_NAME}"
      this.notify('PENDING', 'Build is in progress.')
      this.checkout()

      try {
        this.rebase()
      } catch (e) {
        this.pipeline.error "Unable to rebase on ${this.target}."
      }

      this.pipeline.echo "Executing tests, started at ${this.getCurrentTime()}"

      def command = String.format(
        '%s/sssd-test-suite -c "%s" run --sssd "%s" --artifacts "%s" --update --prune',
        "${this.basedir}/sssd-test-suite",
        "${this.basedir}/configs/${this.system}.json",
        this.codedir,
        this.artifactsdir
      )

      def rc = this.pipeline.sh script: command, returnStatus: true
      if (rc == 255) {
        this.pipeline.error "Timeout reached."
      } else if (rc != 0) {
        this.pipeline.error "Some tests failed."
      }

      this.pipeline.echo "Finished at ${this.getCurrentTime()}"
      this.notify('SUCCESS', 'Success.')
    } catch (FlowInterruptedException e) {
      this.notify('ERROR', 'Aborted.')
      throw e
    } catch (AbortException e) {
      this.notify('ERROR', e.getMessage())
      throw e
    } catch (e) {
      this.notify('ERROR', 'Build failed.')
      throw e
    } finally {
      this.archive()
    }
  }

  def getCurrentTime() {
    def date = new Date()
    return date.format('dd. MM. yyyy HH:mm:ss')
  }

  def checkout() {
    this.pipeline.dir('sssd') {
      this.pipeline.checkout this.pipeline.scm
    }
  }

  def rebase() {
    /* Do not rebase if there is no target (not a pull request). */
    if (!this.target) {
      return
    }

    this.pipeline.echo "Rebasing on ${this.target}"

    // Fetch refs
    this.git(String.format(
      "fetch --no-tags --progress origin +refs/heads/%s:refs/remotes/origin/%s",
      this.target, this.target
    ))

    // Remove left overs from previous rebase if there are any
    this.git("rebase --abort || :")

    // Just to be sure
    this.pipeline.sh "rm -fr '${this.codedir}/.git/rebase-apply' || :"

    // Rebase
    this.git("rebase origin/${this.target}")
  }

  def git(command) {
    this.pipeline.sh "git -C '${this.codedir}' ${command}"
  }

  def archive() {
    this.pipeline.archiveArtifacts artifacts: "artifacts/**",
      allowEmptyArchive: true

    this.pipeline.sh String.format(
      '%s/sssd-ci archive --name "%s" --system "%s" --artifacts "%s"',
      "${this.basedir}/sssd-ci",
      "${pipeline.env.BRANCH_NAME}/${pipeline.env.BUILD_ID}",
      this.system,
      "${artifactsdir}"
    )

    this.pipeline.sh "rm -fr ${this.artifactsdir}"
  }

  def notify(status, message) {
    this.notification.notify(status, message, this.system)
  }
}

/* Manage test run for on demand test. */
class OnDemandTest extends Test {
  String repo
  String branch

  /* @param pipeline Jenkins pipeline context.
   * @param system System to test on.
   * @param notification Notification object.
   * @param repo Repository fetch URL.
   * @param branch Branch to checkout.
   */
  OnDemandTest(pipeline, system, notification, repo, branch) {
    super(pipeline, system, notification)

    this.repo = repo
    this.branch = branch
  }

  def run() {
    this.pipeline.echo "Repository: ${this.repo}"
    this.pipeline.echo "Branch: ${this.branch}"

    super.run()
  }

  def checkout() {
    this.pipeline.dir('sssd') {
      this.pipeline.git branch: this.branch, url: this.repo
    }
  }

  def rebase() {
    /* Do nothing. */
  }

  def archive() {
    this.pipeline.echo 'On demand run. Artifacts are not stored in the cloud.'
    this.pipeline.echo 'They are accessible only from Jenkins.'
    this.pipeline.echo "${this.pipeline.env.BUILD_URL}/artifact/artifacts/${this.system}"
    this.pipeline.archiveArtifacts artifacts: "artifacts/**",
      allowEmptyArchive: true

    this.pipeline.sh "rm -fr ${this.artifactsdir}"
  }
}

def on_demand = params.ON_DEMAND ? true : false
def notification = new Notification(
  this, 'sssd-ci',
  'https://github.com/SSSD/sssd/blob/master/contrib/test-suite/README.md',
  'https://s3.eu-central-1.amazonaws.com/sssd-ci',
  on_demand
)

if (params.SYSTEMS) {
  if (params.SYSTEMS != 'all') {
    systems = params.SYSTEMS.split()
  }
}

try {
  /* Setup nice build description so pull request are easy to find. */
  stage('Setup description') {
    node('master') {
      if (on_demand) {
        /* user: branch */
        def build = currentBuild.rawBuild
        def cause = build.getCause(hudson.model.Cause.UserIdCause.class)
        def user = cause.getUserId()
        currentBuild.description = "${user}: ${params.REPO_BRANCH}"
      } else {
        if (env.CHANGE_TARGET) {
          /* PR XXX: pull request name */
          def title = sh returnStdout: true, script: """
            curl -s https://api.github.com/repos/SSSD/sssd/pulls/${env.CHANGE_ID} | \
            python -c "import sys, json; print(json.load(sys.stdin).get('title'))"
          """
          currentBuild.description = "PR ${env.CHANGE_ID}: ${title}"
        } else {
          /* Branch: name */
          currentBuild.description = "Branch: ${env.BRANCH_NAME}"
        }
      }
    }
  }

  stage('Prepare systems') {
    notification.notify('PENDING', 'Pending.')

    /* Notify that all systems are pending. */
    for (system in systems) {
      notification.notify('PENDING', 'Awaiting executor', system)
    }
  }

  stage('Integration with copr') {
    notification.notify('STARTING', 'Launch copr integration')

    /* 
     * Launch copr following the guidelines from:
     *   https://docs.pagure.org/copr.copr/user_documentation.html#quick-start
     *
     * Prepare the environment; Run a fedora:28 container by:
     *   docker run -it -v $PWD:/sssd -w /sssd fedora:28 /bin/bash
     *
     * Create the file ~/.config/copr with the content got when we follow 
     * this URL: https://copr.fedorainfracloud.org/api/
     *
     * Manual steps followed in a fedora:28 docker container:
     *   dnf install -y epel-release
     *   dnf install -y copr-cli
     *   dnf install -y git openssl sudo curl wget ruby rubygems "rubygem(json)" wget rpm-build dnf-plugins-core libldb-devel
     *   copr-cli create sssd --chroot fedora-rawhide-x86_64  # Only once to create the project
     *   ./contrib/fedora/make_srpm.sh
     *   copr-cli build sssd rpmbuild/SRPMS/sssd-2.2.4-0.fc28.src.rpm
     *
     * NOTE: I am getting a failure state when building, but the logs does not provide
     *       enough information. It needs to research more on it.
     *
     * About the integration into the pipeline, it is needed to create
     * a secret in a file that is mounted in Jenkins agent so that the configuration
     * generated by the API (the token) is accesible when launching the command
     * in the pipeline.
     */    
  }

  /* Run tests on multiple systems in parallel. */
  stage('Run Tests') {
    def stages = [:]
    for (system in systems) {
      def test = null
      if (!on_demand) {
        test = new Test(this, system, notification)
      } else {
        test = new OnDemandTest(
            this, system, notification,
            params.REPO_URL, params.REPO_BRANCH
        )
      }
      stages.put("${system}", {
        // It is needed to create a node in Jenkins with the name 'sssd-ci'
        // to allow those stages run and avoid them to get stuck.
        node("sssd-ci") {
          stage("${system}") {
            test.run()
          }
        }
      })
    }
    parallel(stages)
  }
  stage('Report results') {
    notification.notify('SUCCESS', 'All tests succeeded.')
  }
} catch (FlowInterruptedException e) {
  stage('Report results') {
    notification.notify('ERROR', 'Aborted.')
    throw e
  }
} catch (e) {
  stage('Report results') {
    notification.notify('ERROR', 'Some tests failed.')
    throw e
  }
}
