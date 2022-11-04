# **Deployment 4**

##### **Author: Heriberto Mendoza**

##### **Date: 1 November 2022**

---

### **Objective:**

The goal of this deployment is to continue gaining familiarity with the CI/CD pipeline and familiarity with creating VPCs with Terraform. A simple web application will be deployed across an AWS VPC created with Terraform using Jenkins and gunicorn.

---

#### ***1. Setting up the Jenkins Manager EC2***

Terraform was installed on a Linux server. This server already had the Jenkins Manager installed. The EC2 was configured with a security group that opened ports 22, 80, and 8080 for ingress traffic. Python3-venv and python3-pip packages were also installed to ensure that the server could build the application later.

#### 1a. Jenkins Credentials:

Several sets of credentials were needed for this pipeline to fully functions: Firstly, AWS credentials (access key and secret key) were uploaded (so that Jenkins could have access to AWS). Secondly, a GitHub personal access token was uploaded in order to allow Jenkins to pull from GitHub at various stages in the pipeline. Lastly, an access token for a gmail account was uploaded in order to be able to send the notification and build log. These credentials were configured in Jenkins by accessing the Jenkins UI at `<jenkins IP>:<8080>`.

#### 1b. Jenkins Manager VPC:

The Jenkins EC2 was created in the default VPC/subnet. The default structure is included in the infrastructure diagram.

#### ***2. The Jenkinsfile***

The Jenkinsfile had a total of 7 stages/steps. They are described below.

#### 2a. The 'Build' stage:

```console
stage ('Build') {
    steps {
        sh '''#!/bin/bash
        python3 -m venv test3
        source test3/bin/activate
        pip install pip --upgrade
        pip install -r requirements.txt
        export FLASK_APP=application
        flask run &
        '''
    }
}
```

This stage simply builds the application. A shell script is run in the Jenkins EC2 to create a virtual environment, install required dependencies and run the app on Flask. There were no issues in this stage.

#### 2b. The 'Test' stage:

```console
stage ('Test') {
    steps {
        sh '''#!/bin/bash
        source test3/bin/activate
        py.test --verbose --junit-xml test-reports/results.xml
        '''
    }
    post {
        always {
            junit 'test-reports/results.xml'
        }
    }
}
```

This stage activates the virtual environment created in the build stage and py.test runs all files in the directory that begin with 'test'. In this case, an instance of the application is run and the test tries to access the root page. The response code is checked to verify if it is a successful response. junit subsequently creates and xml repost and saves it in the workspace directory in the Jenkins server.

#### 2c. The 'Init' Stage

```console
stage('Init') {
    steps {
        withCredentials([string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'), \
                         string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key')]) {
                            dir('intTerraform') {
                                sh 'terraform init'
                            }
                         }
    }
}
```

This is the first of the Terraform stages. This stage sets the credentials as the credentials that were uploaded to Jenkins via the UI. It makes sure that the working directory is the proper directory and the command terraform init creates the terraform directory with all the configuration files for AWS.

#### 2d. The 'Plan' Stage

```console
stage('Plan') {
    steps {
        withCredentials([string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'), \
                         string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key')]) {
                            dir('intTerraform') {
                                sh 'terraform plan -out plan.tfplan -var="aws_access_key=$aws_access_key" -var="aws_secret_key=$aws_secret_key"'
                            }
                         }
    }
}
```

The above command `$terraform plan` does several things. It reviews the current state of the infrastructure. It then compares the prior state to the current configuration in the terraform files, and if necessary, identifies changes that need to be made. The -out flag saves the plan to disk and the -var flags set values to the variables "aws_access_key" and "aws_secret_key".

#### 2e. The 'Apply' Stage

```console
stage('Apply') {
    steps {
         withCredentials([string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'), \
                         string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key')]) {
                            dir('intTerraform') {
                                sh 'terraform apply plan.tfplan
                            }
                         }
    }
}
```

The command `$terraform apply` applies the changes proposed in the plan step. It is allowed to do so because the AWS credentials that were saved on Jenkins are passed here as variables that Terraform can recognize. The final infrastructure can be examined further in the documentation.

#### 2f. The 'Destroy' Stage

```console
stage('Destroy') {
    steps {
        withCredentials([string(credentialsId: 'AWS_ACCESS_KEY', variable: 'aws_access_key'), \
                         string(credentialsId: 'AWS_SECRET_KEY', variable: 'aws_secret_key')]) {
                            dir('intTerraform') {
                                sh 'terraform destroy -auto-approve -var="aws_access_key=$aws_access_key" -var="aws_secret_key=$aws_secret_key"'
                            }
                         }
    }
}
```

In this stage, the command `$terraform destroy` destroys the entire infrastructure. The -auto-approve flag bypasses the "yes" confirmation that is normally required (as this pipeline is automated) and the AWS credentials are used for access. This stage was commented in and out of the Jenkinsfile as necessary (commented out to keep the infrastructure up and the app running, and commented back in to clean up).

#### 2g. The 'Post' Stage

```console
post {
    always{
        emailext to: "heri.mendoza9@gmail.com",
        subject: "jenkins build:${currentBuild.currentResult}: ${env.JOB_NAME}",
        body: "${currentBuild.currentResult}: Job ${env.JOB_NAME}\nMore info can be found here: ${env.BUILD_URL",
        attachLog: true
    }
}
```

This final stage is a notification stage. Using the email extension plugin, an email is sent to the 'to' email address with various identifying information and the build log attached. As stated in the beginning, for this to work, credentials to a valid email address had to be uploaded to Jenkins.

#### ***3. Issues***

The only major issue that kept happening was that during a build, Jenkins would freeze and while the build would be running (but never complete), the GUI (on the web browser) would freeze. In order to restore functionality, the Jenkins server would need to be restarted and build restarted. In conversation with colleagues, it was determined that this was most likely a resource issue on the EC2 (insufficient RAM). To prevent builds from freezing, the Jenkins server had to be stopped and started before every build. This also meant that the webhook was rendered useless (as making any changes would trigger a new build, but the Jenkins server could not run successive builds without needing to be restarted).

#### ***4. The Terraform Infrastructure***

The Terraform file created the infrastructure below. A VPC was created in AZ us-east-1a. Two subnets were created, one public and one private. The private subnet was not necessary for this deployment, it was just for practice. The Jenkins EC2 was placed in the public subnet and another EC2 in the private subnet. Because there were private and public subnets, two route tables were needed, a public route table connecting to the internet gateway, and the private route table connecting to the NAT gateway. In the EC2 resource block in the terraform file, a script is called as user data (meaning the script is ran as soon as the instance is created). This script installs git, pip, clones the repository with the source code, and finally, installs the required dependencies and gunicorn to run the application as a --daemon operation.

[VPC Infrastructure Diagram](https://github.com/herimendoza/kuralabs_deployment_4/blob/1d3fc422388dbd7dfdc301caa1feacc14532f276/documentation/images/deploy4_infra.png)

#### ***5. Improvements***

To improve this pipeline and infrastructure:

- If the application is a 3 tier application, it would be wise to create more subnets and place (ideally all) of the tiers in private subnets (the frontend, the application servers, and the database) for security purposes.

- The first point would further necessitate the creation of a bastion host in the public subnet (to allow ssh access to the private subnets and servers).

- An application load balancer would be necessary to allow access to the frontend servers (assuming several frontend servers in different availability zones for redundancy).

#### ***6. Diagrams and Images***

[Jenkins Pipeline](https://github.com/herimendoza/kuralabs_deployment_4/blob/1d3fc422388dbd7dfdc301caa1feacc14532f276/documentation/images/deploy_4_pipeline.png)

[Jenkins Builds](https://github.com/herimendoza/kuralabs_deployment_4/blob/1d3fc422388dbd7dfdc301caa1feacc14532f276/documentation/images/jenkins_builds.png)

[Running Application](https://github.com/herimendoza/kuralabs_deployment_4/blob/1d3fc422388dbd7dfdc301caa1feacc14532f276/documentation/images/application_instance.png)

