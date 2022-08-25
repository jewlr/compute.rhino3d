# escape=`

# see https://discourse.mcneel.com/t/docker-support/89322 for troubleshooting

# NOTE: use 'process' isolation to build image (otherwise rhino fails to install)

### builder image
FROM mcr.microsoft.com/dotnet/sdk:5.0 as builder

# copy everything, restore nuget packages and build app
COPY src/ ./src/
RUN dotnet publish -c Release -r win10-x64 --self-contained true src/compute.sln

### main image
# tag must match windows host for build (and run, if running with process isolation)
# e.g. 1903 for Windows 10 version 1903 host
FROM mcr.microsoft.com/windows:1809

#Copy the fonts and font install script
COPY fonts/* fonts/
COPY InstallFont.ps1 .

#Run font install scriptin powershell
RUN powershell -ExecutionPolicy Bypass -Command .\InstallFont.ps1

#Copy and extract Pufferfish plugin
COPY plugins/* plugins/

#RUN powershell Expand-Archive -Path ./test_plugins.zip -DestinationPath .

# install .net 4.8 if you're using the 1809 base image (see https://git.io/JUYio)
# comment this out for 1903 and newer
RUN curl -fSLo dotnet-framework-installer.exe https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe `
    && .\dotnet-framework-installer.exe /q `
    && del .\dotnet-framework-installer.exe `
    && powershell Remove-Item -Force -Recurse ${Env:TEMP}\*

# install rhino (with “-package -quiet” args)
# NOTE: edit this if you use a different version of rhino!
# the url below will always redirect to the latest rhino 7 (email required)
# https://www.rhino3d.com/download/rhino-for-windows/7/latest/direct?email=EMAIL
RUN curl -fSLo rhino_installer.exe https://www.rhino3d.com/download/rhino-for-windows/7/latest/direct?email=nikhil@jewlr.com `
    && .\rhino_installer.exe -package -quiet `
    && del .\rhino_installer.exe

#Create a libraries directory for the plugin and copy .gha file
RUN powershell mkdir C:\Users\ContainerAdministrator\AppData\Roaming\Grasshopper\Libraries

RUN powershell Copy-Item -Path .\plugins\Pufferfish.gha -Destination "C:\Users\ContainerAdministrator\AppData\Roaming\Grasshopper\Libraries\Pufferfish.gha" `
    && powershell Copy-Item -Path .\plugins\Conductor.gha -Destination "C:\Program` Files\Rhino` 7\Plug-ins\Grasshopper\Components\Conductor.gha" `
    && powershell Copy-Item -Path .\plugins\DefaultValue.gha -Destination "C:\Program` Files\Rhino` 7\Plug-ins\Grasshopper\Components\DefaultValue.gha" `
    && powershell Copy-Item -Path .\plugins\Jewlr.gha -Destination "C:\Program` Files\Rhino` 7\Plug-ins\Grasshopper\Components\Jewlr.gha"

#Copy config files
RUN powershell mkdir C:\Users\ContainerAdministrator\config
COPY config/* C:\Users\ContainerAdministrator\config\


# (optional) use the package manager to install plug-ins
#RUN ""C:\Program Files\Rhino 7\System\Yak.exe"" install jswan
#RUN ""C:\Program Files\Rhino 7\System\Yak.exe"" install hops

# copy compute app to image
COPY --from=builder ["/src/dist", "/app"]
WORKDIR /app

# bind rhino.compute to port 5000
ENV ASPNETCORE_URLS="http://*:5000"
EXPOSE 5000

# uncomment to build core-hour billing credentials into image (not recommended)
# see https://developer.rhino3d.com/guides/compute/core-hour-billing/
ENV RHINO_TOKEN=eyJSYXdPQXV0aDJUb2tlbiI6ICJleUpoYkdjaU9pSklVekkxTmlJc0luUjVjQ0k2SWtwWFZDSjkuZXlKd0lqb2lVRXREVXlNM0lpd2lZeUk2SWtGRlUxOHlOVFpmUTBKRElpd2lZalkwYVhZaU9pSnFURlpRVVhKS1dqZHhkekkzUVVKTU1UVkZLMXBSUFQwaUxDSmlOalJqZENJNkltcHpSMjFKUm10NllUVmxSMGRCVmxwSGFsbGxLMnBqUTJReVJETjRWWGhPTm1aYWJHOUNValpVTDAxUVUxRm1WM2xJVm5aalFuRkJkV05wU0RSbFowVlFNbkZFTW5OSE1sUnhRVXhLYmtwUVFXRlZXV1JPV2xkTU56TXhORXgyYUVGdFJEZE5jRXBQYm05VVlUSlBRVzkwTTJGTmR6Y3JNRVpVTmpnemJIQm9LMVJ4ZHpOdVYwZDBaVVJ4UVRBNEwxWkRMMGcyTjJKeFEwdE9SM05UY21SblpHbGlWVnBLYWpKSWNqRXdNVkJrYVZWVlJXd3lPVkpKVmpkaFlsWnNjMmw0Y1dVM1RITjFOVEo0UVZsTlZYVmlhbWR1UVhjOVBTSXNJbWxoZENJNk1UWTBNamN3TXpZME4zMC5nMFdELTRmRDNjLTJCRERJVm9pYW5ReVRHLUpKNnhoVkJZUl83UlRSakFBIiwgIlNjb3BlIjogWyJwcm9maWxlIiwgIm9wZW5pZCIsICJub2V4cGlyZSIsICJncm91cHMiLCAibGljZW5zZXMiLCAiZW1haWwiXSwgIkdyb3VwSWQiOiAiNDYzMDI5NDQxMDgyMTYzMiIsICJSYXdPcGVuSWRUb2tlbiI6ICJleUpoYkdjaU9pSlNVekkxTmlJc0luUjVjQ0k2SWtwWFZDSjkuZXlKdWIyNWpaU0k2SWpjOFhtMWNjbUYyZTNacUtISmpYSFJSTzBSaWQxeGNKRXhlTTJzaFBXdGNabkZwYzBJNWVXMURkR2N5S1RCYVhIUmFLazFqWlMwOGRucDNRV3RjWERKWlQwZzRYMDhpTENKd2FXTjBkWEpsSWpvaWFIUjBjSE02THk5M2QzY3VaM0poZG1GMFlYSXVZMjl0TDJGMllYUmhjaTh4WldZME5qTXhPV0U1WW1VeVlXUTBNVEV5WVdNNE5EaGlNamswTkRNNE5UOWtQWEpsZEhKdklpd2lZWFZrSWpvaVkyeHZkV1JmZW05dlgyTnNhV1Z1ZENJc0ltTnZiUzV5YUdsdWJ6TmtMbUZqWTI5MWJuUnpMbTkzYm1WeVgyZHliM1Z3Y3lJNlczc2lhV1FpT2lJMU56UXlNREEzTWpNMU16YzVNakF3SWl3aWJtRnRaU0k2SW5Kb2FXNXZJR052YlhCMWRHVnljeUo5TEhzaWFXUWlPaUkwTmpNd01qazBOREV3T0RJeE5qTXlJaXdpYm1GdFpTSTZJbkpvYVc1dklHTnZiWEIxZEdVZ2RHVnpkR2x1WnlKOVhTd2libUZ0WlNJNkltUmhkbWxrSWl3aVkyOXRMbkpvYVc1dk0yUXVZV05qYjNWdWRITXVaVzFoYVd4eklqcGJJbVJoZG1sa2JXTmpkV0ZwWjBCcVpYZHNjaTVqYjIwaVhTd2lZWFJmYUdGemFDSTZJbTV2U0VsWVZIRnZVbGhXTkVNMFVFbDBaMEkxV1VFOVBTSXNJbXh2WTJGc1pTSTZJbVZ1TFhWeklpd2laVzFoYVd4ZmRtVnlhV1pwWldRaU9uUnlkV1VzSW1semN5STZJbWgwZEhCek9pOHZZV05qYjNWdWRITXVjbWhwYm04elpDNWpiMjBpTENKamIyMHVjbWhwYm04elpDNWhZMk52ZFc1MGN5NXRaVzFpWlhKZlozSnZkWEJ6SWpwYlhTd2lZMjl0TG5Kb2FXNXZNMlF1WVdOamIzVnVkSE11YzJsa0lqb2lWM1F4VmxOcVkyVklTM0JXWmxFM1l5dFdjMFJxYkdWUE5sQjZWazVaUm01VGIwTTRTRWM0U1haYU1EMGlMQ0psZUhBaU9qTXlNVGsxTURNMk5EWXNJbUYxZEdoZmRHbHRaU0k2TVRZME1qRXdNelE0T1N3aWFXRjBJam94TmpReU56QXpOalEzTENKamIyMHVjbWhwYm04elpDNWhZMk52ZFc1MGN5NWhaRzFwYmw5bmNtOTFjSE1pT2x0ZExDSmxiV0ZwYkNJNkltUmhkbWxrYldOamRXRnBaMEJxWlhkc2NpNWpiMjBpTENKemRXSWlPaUkxTVRNMk16WTJOREUxTXpnd05EZ3dJbjAuWFB0TUl3TkM0T2dheEFWcVpyZ1o4T1F1SkI4RmpINzBDNkdwTV9oYUdwR3EzUmNEdURsSTBMRHlPM1V0cC1OVkZxMkp6Z1hZT2RpdkVNemNsZ3phbGtOMS11cUE0UjVtdXRWR2J0WUtHV29nbE5kVXg4aFdGWkk1NHRHT3hmR2U5OFQ2VlUyN0pIbmk3UHZHN21YdDE3d29od0JQZUdUamhIRkRFUjFoTldUQ2RsNFZrUmpQc2NFeHF6N0l3SzBPRVJPVFZwYjN1R2hMWFc5QS1PYjFjTlVfckZhcHA4eE91WF9NS3hRNEVGRkF6MHNMc0xLUk4wamI1MjZmcmRwZ21iM1F2ZHdOOTJ1UUpUbFZ3SUlMV2FHOEFlaWlZMmVROGlXWktVa2lqQVFMdnBqcUJOUzctOW1CanBrWXJGZzFFUXBRbTRobWFfejNaRlB2R1MxWXFRIn0=

CMD ["rhino.compute/rhino.compute.exe","--idlespan=600"]