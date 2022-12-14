resource "aws_s3_bucket" "s3_logging_bucket" {
    bucket                    = "${var.environment}-${local.account_id}-codebuild-logs"
    #force_destroy            = false
    force_destroy             = true
}

resource "aws_s3_bucket" "codepipeline_artifact_bucket" {
    bucket                    = "${var.environment}-${local.account_id}-codepipeline-artifact-bucket"
    #force_destroy            = false
    force_destroy             = true
}

#################################################################
############# Build/Deploy Admin static site ####################
#################################################################

resource "aws_codebuild_project" "codebuild_project_admin_site" {
  name                          = "${var.environment}-build-admin-site"
  description                   = "Build codebuild project"
  build_timeout                 = "5"
  service_role                  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type                        = "S3"
    location                    = aws_s3_bucket.s3_logging_bucket.bucket
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = "true"

    environment_variable {
      name                      = "terraform"
      value                     = "true"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name              = "log-group"
      stream_name             = "log-stream"
    }

    s3_logs {
      status                  = "ENABLED"
      location                = "${aws_s3_bucket.s3_logging_bucket.id}/codebuild-log"
    }
  }

  file_system_locations {
    type                      = "EFS"
    identifier                = "GREEN"
    location                  = "${aws_efs_file_system.admin_files_green.id}.efs.us-east-2.amazonaws.com:/"
    mount_point               = "/mnt/efs/green"
  }

  source {
    type                      = "CODEPIPELINE"
    buildspec = <<EOF
    version: 0.2

    phases:
      install:
        runtime-versions:
          nodejs: 14
        commands:
          - apt update -y
          - echo "build command"
          ### We can see it on port 8081 after deploy ###
          - |
            #!/bin/bash
            tee index.html <<'EOF'
            <!DOCTYPE html>
            <html lang="en">
              <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <meta http-equiv="X-UA-Compatible" content="ie=edge">
                <title>My Website Version Green </title>
                <link rel="stylesheet" href="./style.css">
                <link rel="icon" href="./favicon.ico" type="image/x-icon">
              </head>
              <body>
                <main>
                    <h1>Welcome to My Website Version Green v4</h1>
                </main>
                    <script src="index.js"></script>
              </body>
            </html>
            
          # - npm i
          # - npm run build:dev
          - ls
          - ls $CODEBUILD_GREEN
          - cp index.html $CODEBUILD_GREEN
    EOF
  }
  
  vpc_config {
    vpc_id                    = aws_vpc.main_vpc.id
    subnets                   = ["${aws_subnet.private_codebuild.*.id[0]}", "${aws_subnet.private_codebuild.*.id[1]}"]
    security_group_ids        = [aws_security_group.codebuild.id]

}
}

################## Deploy New Version ###########################
resource "aws_codebuild_project" "codebuild_deploy_admin_site" {
  name                        = "${var.environment}-deploy-admin-site"
  description                 = "Deploy codebuild project"
  build_timeout               = "5"
  service_role                = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type                        = "S3"
    location                    = aws_s3_bucket.s3_logging_bucket.bucket
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = "true"

    environment_variable {
      name                      = "terraform"
      value                     = "true"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name                = "log-group"
      stream_name               = "log-stream"
    }

    s3_logs {
      status                    = "ENABLED"
      location                  = "${aws_s3_bucket.s3_logging_bucket.id}/codebuild-log"
    }
  }

  file_system_locations {
    type                        = "EFS"
    identifier                  = "BLUE"
    location                    = "${aws_efs_file_system.admin_files.id}.efs.us-east-2.amazonaws.com:/"
    mount_point                 = "/mnt/efs/blue"
  }

  file_system_locations {
    type                        = "EFS"
    identifier                  = "GREEN"
    location                    = "${aws_efs_file_system.admin_files_green.id}.efs.us-east-2.amazonaws.com:/"
    mount_point                 = "/mnt/efs/green"
  }

  source {
    type                        = "CODEPIPELINE"
    buildspec                   = "Development/templates/buildspec/buildspec_deploy_staticsite.yml"
  }

  vpc_config {
    vpc_id                      = aws_vpc.main_vpc.id
    subnets                     = ["${aws_subnet.private_codebuild.*.id[0]}", "${aws_subnet.private_codebuild.*.id[1]}"]
    security_group_ids          = [aws_security_group.codebuild.id]

  }
}

##################### Pipeline for Admin Site ##########################
resource "aws_codepipeline" "codepipeline_admin_site" {
  name                          = "${var.environment}-admin-site"
  role_arn                      = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location                    = aws_s3_bucket.codepipeline_artifact_bucket.bucket
    type                        = "S3"
  }

  stage {
    name = "Source"

    action {
      name              = "Source"
      category          = "Source"
      owner             = "AWS"
      provider          = "CodeStarSourceConnection"
      version           = "1"
      output_artifacts  = ["SourceArtifact"]

      configuration = {
        BranchName       = "main"
        ConnectionArn    = var.connections_connection
        FullRepositoryId = "ykrzal/infrastructure"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceArtifact"]
      version          = "1"

      configuration = {
        ProjectName    = "${aws_codebuild_project.codebuild_project_admin_site.name}"
      }
    }
  }

stage {
  name = "Apporve-Swap"

  action {
    name                = "Apporve-Swap"
    category            = "Approval"
    owner               = "AWS"
    provider            = "Manual"
    version             = "1"
  }
}

  stage {
    name = "Deploy"

    action {
      name              = "Deploy"
      category          = "Build"
      owner             = "AWS"
      provider          = "CodeBuild"
      input_artifacts   = ["SourceArtifact"]
      version           = "1"

      configuration = {
        ProjectName     = "${aws_codebuild_project.codebuild_deploy_admin_site.name}"
      }
    }
  }
}
