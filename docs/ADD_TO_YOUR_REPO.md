# Add this downloadable project to your existing repository

This archive contains the project files, including `.github/workflows`, but no `.git` directory.
It has not been pushed to GitHub. Your local GitHub login is needed to publish it.

If you already cloned the repository, copy these project files into that checkout, replacing
its README but preserving its `.git` directory. On macOS, from the extracted project folder:

```bash
# Replace the destination with your EXISTING clone's absolute path.
rsync -av --exclude='.git/' ./ /path/to/Azure-Cloud-ETL-project/
cd /path/to/Azure-Cloud-ETL-project
git switch -c feature/complete-etl-demo
git add .
git commit -m "Add runnable Azure retail ETL demo with Terraform and CI/CD"
git push -u origin feature/complete-etl-demo
```

Open GitHub and create a pull request to main. Review the diff and CI results before merging.
Do not run `git init` inside an existing checkout and do not copy one `.git` directory into another.
GitHub Actions workflow files are included; CD remains manual and needs the setup in CICD.md.
