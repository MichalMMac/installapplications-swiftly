# InstallApplications Swiftly

**Current development phase: ALPHA. DO NOT USE IN PRODUCTION!!!**

InstallApplications Swiftly (**IAS**) is a Swift reimplementation of the popular Python based tool [InstallApplications](https://github.com/macadmins/installapplications) (**IA**)
created by [@erikng](https://github.com/erikng).

## IAS vs IA

IAS has several advantages over the original IA:

- No Python dependency. Implementation done purely with Swift and Apple frameworks.
- Smaller package footprint and faster installation. Current package size is less than 1 MB.
  There are <10 files to install. IA package size is around 40 MB and it contains more
  than 6000 files because of the bundled Python 3 framework.
- Faster workflow execution:
  - Items are downloaded in parallel using separate threads.
  - Ability to run designated tasks in parallel.


## About

IAS is a bootstrap tool to be used primarily during the macOS MDM Enrolment.
Main goal is to easily deploy other bootstrap scripts and packages right after the MDM enrolment.
List of packages and script is maintained server side so you don't have to modify your
MDM bootstrap package every time you want to make a change to your bootstrap process.

IAS is ment to be deployed by the MDM using the `InstallEnterpriseApplication` command.
Your MDM has to support bootstrap package functionality. You can find more on this topic
in the original IA README -> [MDMs that support Custom DEP](https://github.com/macadmins/installapplications#mdms-that-support-custom-dep).

IAS requires macOS 11.1 or newer.


## How does it work

General outline of the entire IAS lifecycle.

### Preparation

Steps you need to do to prepare IAS for deployment:

1. Prepare signed distribution package containing IAS and its configuration. See section [Preparing IAS for deployment](#preparing-ias-for-deployment).
2. Import IAS package into your MDM and assign it to desired set of Macs.
3. Create JSON control file and serve it with a webserver. See section [JSON control file](#json-control-file).
4. Make sure all package abd script URLs contained in the JSON control file are reachable.

### Deployment

1. Mac enrolls into MDM.
2. MDM sends a `InstallEnterpriseApplication` command to inform the device is should download and install IAS package.
3. Package script loads the IAS LaunchDaemon `iasd` and LaunchAgent `iasagent`.
4. `isasd` downloads the JSON control file from URL specified by its configuration.
5. `isasd` starts executing the Phases. See section [Phases](#phases).
6. If there is a userland phase defined in the JSON control file,
   IAS will wait until there is active user GUI session before installing.
  `iasagent` is used to execute scripts on behalf of the logged in user.
7. After the work is done `isasd` deletes alls its files, unloads itself and the `iasagent` from the launchd and exists.


## Phases

There are three phases of the bootstrap process.

### preflight

You can specify only rootscript items for this phase.
`preflight` phase is useful for running IAS on previously deployed machines or if you simply want to re-run it.

If all `preflight` scripts exit with zero exit code, `isad` finishes bootstrap process, bypassing the `setupassistant` and `userland` phases.

If one of the `preflight` scripts exists with non-zero exit code, `isad` continues to the setupassistant phase.

### setupassistant

At the beginning of s`etupassistant` phase `isad` starts downloding items for the `setupassistant` and `userland` phases.

`setupassistant` phase should only contain rootscript a package items which can be installed without need for active user session.

### userland

`userland` phase starts after the user logs in and all items in the `setupassistant` phase has been executed.
It can contain package, rootscript or userscript items.
Items of type userscript are run by the `iasagent` with the privileges of the logged in user.

Running items in the `userland` phase is extremely useful for situations where bootstrap process needs to communicate with the user via GUI elements.


## Preparing IAS for deployment

### Deploying release package

**NOT YET IMPLEMENTED**

~When IAS is configured only using the configuration profile from MDM you can deploy release package without any modifications.
You need to make sure MDM issues command to install the configuration profile **before** the command to install the IAS package.~

### Preparing custom package

IAS releases include a zip archive containing the `ias-munkipkg` directory to used with the [munkipkg](https://github.com/munki/munki-pkg) to create the IAS package.

Alternatively you can use `munkipkg` directory from the git repository itself. However you need to include binaries manually.

#### Adding the configuration

Currently there are two ways to provide configuration for IAS.

1. Put the file named `ias.plist`into the directory containing `iasd` binary.
2. Provide path to config plist as a first argument of `iasd`. This means editing the LaunchDaemon plist:

```xml
<key>Program</key>
<string>/Library/installapplications/iasd</string>
<key>ProgramArguments</key>
<array>
    <string>/path/to/your/iasd/config.plist</string>
</array>
```

If for some reason you manage do do both, file provided as an argument takes precedence.

#### Signing

Distribution package **must** be signed with a valid Apple installer signing certificate.
Without the signature, package can not be deployed by the MDM.
Learn more about Apple Developer programs and certificates at Apple Developer [portal](https://developer.apple.com).

You can use the `munkipkg` to sign the package by adding `signing_info` dictionary to `build-info` file:

```xml
<key>signing_info</key>
<dict>
    <key>identity</key>
    <string>Mac Installer: Your package signing certificate name (XXXXXXXXXXX)</string>
    <key>timestamp</key>
    <true/>
</dict>
```

#### Bulding the package

You build the package using the `munkipkg`:

```shell
munkipkg /path/to/munkipkg/directory
```

By default all package files are installed with the ownership `root:wheel` and the unix permissions set to `0755` (directories) or `0644` (files).
With these default every macOS user can read them. This might not be desirable in all situations.
For example if you put HTTP authentication credentials into the configuration file you would like to prevent the user from reading it easily.
If you want to change these permission to more restrictive values (f.e. `0700`|`0600`) you can do that with the `pkgbuild` `--ownership` flag.
Inspect `man pkgbuild` and  corresponding `munkipkg` [documentation](https://github.com/munki/munki-pkg#building-a-package) for more information.


## Settings

Settings are provided by configuration plist file (section [Adding the configuration](#adding-the-configuration)).

Setting key            | Default value                  | Type    | Description
---------------------- | ------------------------------ | ------- | ------------
**General settings**   |                                |         |
HTTPAuthPassword       |                                | String  | Password for HTTP Basic or HTTP Digest authentication. Applied to all HTTP authentication challenges.
HTTPAuthUser           |                                | String  | Username for HTTP Basic or HTTP Digest authentication. Applied to all HTTP authentication challenges.
JSONURL                |                                | String  | **REQUIRED** URL of the JSON control file. HTTPS strongly recommended. If you want to use `SkipJSONValidation` setting and include the JSON control file inside the IAS package you can provide any url but the last component of this URL must match the file name of the JSON control file.
Reboot                 | false                          | Bool    | When true `iasd` will initiate macOS reboot before it exits.
**Customization**      |                                |         |
HashCheckPolicy        | Strict                         | String  | Can be either `Strict`, `Warning` or `Ignore`. See section [Hack check policy](#hack-check-policy).
InstallPath            | `/Library/installapplications` | String  | IAS main directory. `iasd` ensures this directory is created (including the `userscripts` subdirectory) before downloading the JSON control file. `iasd` also deletes this directory during the cleanup.
Identifier             | `cz.macadmin.ias`              | String  | IAS identifier. See section [Identifiers](#identifiers) for more information.
LaunchDaemonIdentifier | `cz.macadmin.iasd`             | String  | IAS LaunchDaemon identifier. See section [Identifiers](#identifiers) for more information.
LaunchAgentIdentifier  | `cz.macadmin.iasagent`         | String  | IAS LaunchAgent identifier. See section [Identifiers](#identifiers) for more information.
MinDownloadConcurrency | 1                              | Integer | See section [Parallel downloads](#parallel-downloads) for more information.
MaxDownloadConcurrency | 4                              | Integer | See section [Parallel downloads](#parallel-downloads) for more information.
MaximumRedownloads     | 3                              | Integer | Maximum number of redownload attempts.
SkipJSONValidation     | false                          | Bool    | When true the JSON control file is not deleted and redowloaded if found inside the `InstallPath` directory at begging of the `iasd` run.
WaitForAgentTimeout    | 86400                          | Integer | Amount of time in seconds indicating how long `iasd` is willing to wait for `iasagent` to connect when beginning the userland phase. When reached, `iasd` exits without doing the clean up.
**Troubleshooting**    |                                |         |
DryRun                 | false                          | Bool    | When true `iasd` downloads all the items but nothing is installed/executed. If the userland phase is present `iasd` waits for agent to connect (Issue #11).

Example: [SampleOptions.plist](SampleOptions.plist).

### Hack check policy

IAS can compare known SHA256 digest value to the digest computed from the actual downloaded file.
Hash checking only applies to items with the `url` key set. IAS never checks hash digest of items which are ment not to be downloaded.
`HashCheckPolicy` has three modes how it verifies dowloaded item integrity:

- **Strict (Default)**: After the item download, SHA256 digest of the file is computed and compared to value of item `hash` key in the JSON control file.
  If the hash digests does not match, file is downloaded again until the digest value matches or `MaximumRedownloads` limit is reached.
  If the hash digest still does not match after the last redownload attempt, download is considered failed.
  Also if the `hash` is missing from the JSON control file, download is considered failed.
  This is the same behavior as in the original IA tool.
- **Warning**: SHA256 digest is compared to the `hash` key in the JSON control file.
  If the hash digests does not match, warning is issued but download is considered succesfull.
  If the `hash` is missing from the JSON control, warning is issued but download is considered succesfull.
- **Ignore**: SHA256 is never computed or compared. Finished downloads are always considered succesfull.

### Identifiers

IAS uses four identifiers:

- `Identifier`: Tool identifier. Used mainly for system log subsystem identifier. See section [Logging](#logging).
- `LaunchDaemonIdentifier`: Identifier of the IAS LaunchDaemon.
- `LaunchAgentIdentifier`: Identifier of the IAS LaunchAgent.
- `XPCServiceIdentifier`: Currently not configurable. Always `cz.macadmin.ias.xpc`.

You can change the identifiers without modifying the source code and compiling binaries via respective [Settings](#settings).
See following sections how to do that.

There are places where configurable identifiers do not apply:

- Log subsystem id before the settings are loaded.
- `iasagent` log subsystem during the XPC initialization.
- `XPCServiceIdentifier`.

Some of theses cases might be mitigated in the future by implementing command line arguments.
For now, if you want to completely change the values of the identifiers, edit their constants in `Shared/Constants.swift` and compile the binaries.

#### Changing the main Identifier

To change the id of the log subsystem, set the `Identifier` to desired value key using the [Settings](#settings).

To change the package id of the IAS package modify the value of the `identifier` key in munkipkg build-info file and build the IAS package.

#### Changing the LaunchDaemonIdentifier

You need to change the identifier in **all** of the following places:

- Set the `LaunchDaemonIdentifier` key to `your.new.daemon.id` using the [Settings](#settings).
- Rename the LaunchDaemon file `cz.macadmin.iasd.plist` to `your.new.daemon.id.plist`.
- Change the value of the LaunchDaemon `Label` key to `your.new.daemon.id`.
- Change the value of the `launch_daemon_id` variable in the IAS package **preinstall** script to `your.new.daemon.id`.
- Change the value of the `launch_daemon_id` variable in the IAS package **postinstall** script to `your.new.daemon.id`.

#### Changing the LaunchAgentIdentifier

You need to change the identifier in **all** of the following places:

- Set the `LaunchAgentIdentifier` key to `your.new.agent.id` using the [Settings](#settings).
- Rename the LaunchAgent file `cz.macadmin.iasgent.plist` to `your.new.agent.id.plist`.
- Change the value of the LaunchAgent `Label` key to `your.new.agent.id`.
- Change the value of the `launch_agent_id` variable in the IAS package **preinstall** script to `your.new.agent.id`.
- Change the value of the `launch_agent_id` variable in the IAS package **postinstall** script to `your.new.agent.id`.

### Parallel downloads

IAS downloads the files in parallel. There are two options to control this bahavior:

- At the start of preflight and setupassistant phases number of allowed concurrent downloads starts at `MinDownloadConcurrency`.
- With each completed download **level of concurrency is increased by one** until the `MaxDownloadConcurrency` is reached.


## JSON control file

IAS is 100% compatible with the IA JSON control file format. However there are few new options.

Item keys                  | Default value                  | Type    | Description
-------------------------- | ------------------------------ | ------- | ------------
**Standard general keys**  |                                |         |
file                       |                                | String  | **REQUIRED** System path where the item file is present or is going to be downloaded to.
name                       |                                | String  | **REQUIRED** Name of the item. Used for logging purposes.
type                       |                                | String  | **REQUIRED** Item type. One of the following: `package`, `rootscript` or `userscript`. See sections [Packages](#packages) and [Scripts](#scripts).
donotwait                  | false                          | Bool    | When true `iasd` starts the item execution but does not wait for it to finish and proceeds to the next item.
hash                       |                                | String  | SHA256 digest of the item file. Required unless `HashCheckPolicy` is set to `Ignore`.
pkg_required               | false                          | Bool    | When true package is always installed by the `iasd` with no regard to existing package receipt
url                        |                                | String  | URL of the item file where it can be downloaded from.
**New general keys**       |                                |         |
fail_policy                | failable_execution             | String  | One of the following: `failable`, `failable_execution`, `failure_is_not_an_option`. See section [Fail policy](#fail-policy).
parallel_group             |                                | String  | Parallel group id. See section [Parallel groups](#parallel-groups).
**Package specific keys**  |                                |         |
packageid                  |                                | String  | Package identifier. See section [Package](#package).
version                    |                                | String  | Package version. See section [Package](#package).

Example:

```json
{
  "preflight": [
    {
      "file": "/Library/installapplications/preflight1.sh",
      "hash": "sha256 hash",
      "name": "First Preflight Script",
      "type": "rootscript",
      "url": "https://domain.tld/preflight1.sh"
    },
    {
      "file": "/Library/installapplications/preflight2.sh",
      "hash": "sha256 hash",
      "name": "Second Preflight Script",
      "type": "rootscript",
      "url": "https://domain.tld/preflight2.sh"
    }
  ],
  "setupassistant": [
    {
      "file": "/Library/installapplications/package1.pkg",
      "hash": "sha256 hash",
      "name": "Package 1 installed in parallel with the Rootscript 1 run",
      "packageid": "com.package.package1",
      "parallel_group": "alpha",
      "type": "package",
      "url": "https://domain.tld/package1.pkg",
      "version": "1.0"
    },
    {
      "file": "/Library/installapplications/rootscript1.py",
      "hash": "sha256 hash",
      "name": "Rootscript 1 run in parallel with the Package 1 installation",
      "parallel_group": "alpha",
      "type": "rootscript",
      "url": "https://domain.tld/userland_examplerootscript.py"
    }
  ],
  "userland": [
    {
      "fail_policy": "failure_is_not_an_option",
      "file": "/Library/installapplications/package2.pkg",
      "hash": "sha256 hash",
      "name": "Package 2 installed in the userland phase which must not fail for IAS to proceed",
      "packageid": "com.package.package2",
      "type": "package",
      "url": "https://domain.tld/package2.pkg",
      "version": "1.0"
    },
    {
      "donotwait": true,
      "file": "/Library/installapplications/rootscript2.sh",
      "hash": "sha256 hash",
      "name": "Rootscript 2 run asynchronously",
      "type": "rootscript",
      "url": "https://domain.tld/rootscript2.sh"
    },
    {
      "file": "/Library/installapplications/userscripts/userscript.sh",
      "hash": "sha256 hash",
      "name": "Userscript to be run by iasagent",
      "type": "userscript",
      "url": "https://domain.tld/userscript.py"
    }
  ]
}
```

### Creating JSON

JSON control file can be created manually or automatically generated by some other tool.
Check out [generatejson.py](https://github.com/macadmins/installapplications#creating-your-json) from the original IA.

### Hash digests

You can compute file SHA256 digest by using the command: `shasum -a 256 /path/to/file`.

Read more about hash digest checking in the [Hack check policy](#hack-check-policy) section.

### Packages

IAS uses `packageid` and `version` to check whether package receipt exits or not.
If receipt is found and already installed version is the same or newer than version of the item, package is considered installed.

In the default state IAS does not attempt install packages it considers already installed.
You can override this behavior by providing the `pkg_required` key.
Package items with `pkg_required` set to true are alway installed by IAS.
Omitting `packageid` or/and `version` keys leads to the same result but generates warning message in the log.

Since packages can only be installed by root user = `iasd`, their file permissions are set to `0o600`.

### Scripts

Origial IA tool required to put items of type `userscript` into separate `userscripts` directory.
With IAS you can put `userscript` item anywhere you like because it is downloaded by the `iasd` daemon running as root.

However IAS creates `userscripts` directory inside `InstallPath` for compatibility with existing JSON control files.

Item file unix permissions:

- `rootscript`: `0700`
- `userscript`: `0755`

### Fail policy

Every item can have its own `fail_policy`. Three are three options:

- `failable`: Item download or execution can fail. IAS logs an error but proceeds to the next item.
- `failable_execution` (DEFAULT): Item execution can produce non-zero exit code but download must succeed. If item download fails IAS aborts the entire run.
- `failure_is_not_an_option`: If download fails or execution produces non-zero exit code IAS aborts the entire run.

### Parallel groups

All subsequent items with the same `parallel_group` identifier can be executed in parallel.
This does not guarantee execution of these items to start at the same time since some of them might not yet be downloaded.
IAS does wait for all items in the same `parallel_group` to finish their execution before proceeding to the following item (or parallel group).

You can combine `parallel_group` with `donotwait`.
Tasks marked with `donotwait` start package install or script execution but do not wait for them finish.
IAS waits only for the task responsible of starting the work but not the work itself since that was launched fire-and-forget style.

Example

```json
      "name": "item1",
      "parallel_group": "alpha",
      ...
      "name": "item2",
      "parallel_group": "alpha",
      ...
      "name": "item3",
      "parallel_group": "beta",
      ...
      "name": "item4",
      "parallel_group": "beta",
      ...
      "donotwait": true,
      "name": "item5",
      "parallel_group": "beta",
      ...
      "name": "item6",
      "parallel_group": "alpha",
```

1. Start execution of `item1` and `item2` (`alpha` parallel group) as soon as their individual downloads are complete.
2. Wait for the `item1` and `item2` to finish.
3. Start execution of `item3`, `item4` and `item5` (`beta` parallel group) as soon as their individual downloads are complete.
4. Wait for the `item3` and `item4` to finish. No need to wait for `item5` since it is marked with `donotwait`.
5. Start execution of `item6` as soon as its download is complete. Note the `parallel_group` set to `alpha`.
   This is probably by mistake, `parallel_group` identifier should be gamma.
   IAS treats this as third parallel group regardless of the name because there are other non-alpha items in between.


## HTTP behavior

### Authentication

You can configure IAS to authenticate HTTP requests by providing `HTTPAuthPassword` and `HTTPAuthUser` settings.
HTTP authentication happens on demand (only when server requires it).
Supported methods are HTTP Basic and HTTP Digest.

### Redirects

HTTP redirects are followed automatically.


## Logging

`iasd` and `iasagent` do not print anything to stdout or stderr.
All log messages are sent to the macOS system log instead.
You can use Console.app or `log` command line tool to inspect them.

You can filter them out by specifying the subsystem: `cz.macadmin.ias` (default).

Please note even when you change the `Identifier` some of the log messages are still marked
with subsystem `cz.macadmin.ias`. Read more about this in [Identifiers](#identifiers) section.

### Examples

View all past IAS messages:

```shell
log show --predicate 'subsystem == "cz.macadmin.ias"'
```

View IAS messages within the last hour including those with info and debug severity levels:

```shell
log show --last 1h --info --debug --predicate 'subsystem == "cz.macadmin.ias"'
```

Stream new IAS messages:

```shell
log stream --predicate 'subsystem == "cz.macadmin.ias"'
```
