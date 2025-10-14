# `lrc-scripts`: Useful Scripts for Lawrencium

### `request_cert.sh`

The script `request_cert.sh` when used with `-p lrc` creates a certificate in your `~/.ssh/ssh_certs` directory with the name `lrc_cert`. When prompted, enter your Lawrencium username, PIN and OTP.

```
./request_cert.sh -p lrc
```

The certificate is valid for 12 hours and you can then use the `ssh` command as shown below to login to Lawrencium.

```
ssh -i ~/.ssh/ssh_certs/lrc_cert -l username lrc-login.lbl.gov
```
where `username` is your Lawrencium username. You can also add the following lines to your `~/.ssh/config` file so that you don't have to specify the certificate file and the username and simply use `ssh lrc-login` to login to Lawrencium.

```
Host lrc-login
    User username
    HostName lrc-login.lbl.gov
    IdentityFile ~/.ssh/ssh_certs/lrc_cert
```
