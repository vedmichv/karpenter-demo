# Cloud9 setup

### Install terminal tools
Configure git and generate ssh . Copy on the final step id_rsa.pub to your github account
```bash
ssh-keygen -t rsa
```
enter-enter-enter
```bash
git config --global user.email "YOUR_EMAIL@EMAIL.COM"
git config --global user.name "YOUR NAME"
cat ~/.ssh/id_rsa.pub 
```
**Install kubectl**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

**Update awscli**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Install jq, envsubst (from GNU gettext utilities) and bash-completion**
```bash
sudo yum -y install jq gettext bash-completion moreutils zsh figlet
mkdir -p ~/.local/share/fonts/figlet-fonts/
git clone https://github.com/xero/figlet-fonts.git ~/.local/share/fonts/figlet-fonts/
gem install lolcat
```

Install yq for yaml processingHeader anchor link
```bash
echo 'yq() {
  docker run --rm -i -v "${PWD}":/workdir mikefarah/yq "$@"
}' | tee -a ~/.bashrc && source ~/.bashrc

```
For **Bash** just add the following lines into your _**.bashrc**_ file:

```bash
echo 'function lolbanner() {
  figlet -c -f ~/.local/share/fonts/figlet-fonts/3d.flf $@ | lolcat
}' | tee -a ~/.bashrc && source ~/.bashrc
```

**Edit**
```bash
mkdir -p  ~/.config/fish/
# vim ~/.config/fish/config.fish
# set paste
echo 'function lolbanner
    echo
    figlet -c -f ~/.local/share/fonts/figlet-fonts/3d.flf $argv | lolcat
    echo
end' | tee -a ~/.config/fish/config.fish
```


**Verify the binaries are in the path and executable**
```bash
for command in kubectl jq envsubst aws
  do
    which $command &>/dev/null && echo "$command in path" || echo "$command NOT FOUND"
  done
```

**Enable kubectl bash_completion**
```bash
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo "alias k=kubectl" >> ~/.bashrc
echo "complete -F __start_kubectl k" >> ~/.bashrc
```

**Install fzf**
```bash
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

kubectx + kubens
```bash
sudo curl https://raw.githubusercontent.com/blendle/kns/master/bin/kns -o /usr/local/bin/kns && sudo chmod +x $_
sudo curl https://raw.githubusercontent.com/blendle/kns/master/bin/ktx -o /usr/local/bin/ktx && sudo chmod +x $_
```

Install aliases:
```bash
wget https://raw.githubusercontent.com/ahmetb/kubectl-aliases/master/.kubectl_aliases -O ~/.kubectl_aliases
echo "[ -f ~/.kubectl_aliases ] && source ~/.kubectl_aliases" >> ~/.bashrc 
echo "alias kgn='kubectl get nodes -L beta.kubernetes.io/arch -L eks.amazonaws.com/capacityType -L beta.kubernetes.io/instance-type -L eks.amazonaws.com/nodegroup -L topology.kubernetes.io/zone -L karpenter.sh/provisioner-name -L karpenter.sh/capacity-type'" | tee -a ~/.bashrc
source ~/.bashrc
```

Install krew to install k8s plugins (install also resource-capacity)
```bash
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
# works only for cloud9

echo 'export PATH="/home/ec2-user/.krew/bin:$PATH"' | tee -a ~/.bashrc && source ~/.bashrc
kubectl krew install resource-capacity
```

eksctl 
```bash
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
```

Other tools
```bash
curl -sS https://webinstall.dev/k9s | bash
npm install -g c9
curl -Lo ec2-instance-selector https://github.com/aws/amazon-ec2-instance-selector/releases/download/v2.4.0/ec2-instance-selector-`uname | tr '[:upper:]' '[:lower:]'`-amd64 && chmod +x ec2-instance-selector
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Amazon EKS Node Viewer [GitHub - awslabs/eks-node-viewer: EKS Node Viewer](https://github.com/awslabs/eks-node-viewer) 
```bash
go install github.com/awslabs/eks-node-viewer/cmd/eks-node-viewer@latest
```

### Configure Cloud9 
Disable Cloud9 AWS temporary credentials
```bash
aws cloud9 update-environment  --environment-id $C9_PID --managed-credentials-action DISABLE
rm -vf ${HOME}/.aws/credentials
```

**Apply the right role for the cloud9 machine**

Configure aws cli with your current region as default.
```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

```

Check if AWS_REGION is set to desired region
```bash
test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set
```

Save these into bash_profile
```bash
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region
```


### Increase size of cloud9

```bash
pip3 install --user --upgrade boto3
export instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
python -c "import boto3
import os
from botocore.exceptions import ClientError 
ec2 = boto3.client('ec2')
volume_info = ec2.describe_volumes(
    Filters=[
        {
            'Name': 'attachment.instance-id',
            'Values': [
                os.getenv('instance_id')
            ]
        }
    ]
)
volume_id = volume_info['Volumes'][0]['VolumeId']
try:
    resize = ec2.modify_volume(    
            VolumeId=volume_id,    
            Size=30
    )
    print(resize)
except ClientError as e:
    if e.response['Error']['Code'] == 'InvalidParameterValue':
        print('ERROR MESSAGE: {}'.format(e))"
if [ $? -eq 0 ]; then
    sudo reboot
fi
```

## Add fancy intro that we are going to start Demo 

#lolbanner 
```sh
lolbanner Demo Karpenter
```



For **ZSH** it is very similar, just a slight difference, add the following function to your _**.zshrc**_ file:

```zsh
echo 'function lolbanner {
  figlet -c -f ~/.local/share/fonts/figlet-fonts/3d.flf $@ | lolcat
}' | tee -a ~/.zshrc 
```

For zsh 
```bash
source <(kubectl completion zsh)  
echo '[[ $commands[kubectl] ]] && source <(kubectl completion zsh)' >> ~/.zshrc
echo "alias k=kubectl" >> ~/.zshrc
echo "complete -F __start_kubectl k" >> ~/.zshrc
source ~/.zshrc
```



Install and configure zsh as default bash
```bash
sudo lchsh $USER
# enter /bin/zsh
# chsh -s $(which zsh)
```
Install oh-my-zsh
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```
Install theme
```bash
vim ~/.zshrc
# edit and add the theme
ZSH_THEME="powerlevel10k/powerlevel10k"
source ~/.zshrc
```

Clone the powerlevel10k theme repository:
```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```
