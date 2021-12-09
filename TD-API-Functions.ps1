#####################################################################
#
#   Script: TD-API-Functions.ps1
#
#   Contains a series of functions used for working with AD accounts
#   And the TDX API
#   
#   Author: dparr@granite-it.net
#   Created: Sept. 2021
#
#
#####################################################################


#Create LogFile.  Can be statically set to a specific path
$Global:Logfile = read-host "Key In full path to log file"

#Global Variables for Team Dynamix API Integration 
#Unique to Your Institution
$Global:apiUser = 'td_api_username'
$Global:apiPW = 'SuperSecretPassword' 
$Global:BEID = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
$Global:WebServicesID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$Global:contentType = 'application/json'
$Global:tdURL = 'https://td.acmeinc.ca/TDWebApi/api'
$Global:app_id = 55  #Unique to Your Institution
$Global:UUIDs = @() #all TD Person UUIDs get added to this variable so that they can be have a desktop bulk updated
$DateString = get-date -format "dd-MM-yyyy"


clear-host

Function Add-ADUser2TD {
    <#
    .SYNOPSIS
    When Passed an AD User Object this Function will Determine if the user needs to be added or updated in Team Dynamix
    It will then pass the info to the correct function based on Usertype.
    
    .DESCRIPTION
    Long description
    
    .PARAMETER ADUser
    A User Object from AD with all Properties exposed or at a minimum the following Properties:
        -Department
        -EmployeeNumber
        -ExtensionAttribute1
        -Office
        -OfficePhone
        -OtherMailbox
    
    .EXAMPLE
    $AdUser = Get-aduser -identity RRabbit -properties *
    Add-ADUser2TD -Aduser $Aduser
    
    .NOTES
    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
        ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    
    In Authors environment Extension attribute1 should contain a value with the user type (employee, student, etc.)
    This is Unique to this Institution: you may want to omit Or Severely Alter this Function code
    #>
    Param(
        [Parameter(mandatory = $true)]
        $ADUser
    )
    [string]$Username = $Aduser.SamAccountName
    [string]$Email = $AdUser.UserPrincipalName
    [string]$DN = $ADUser.DistinguishedName
    [string]$AlternateEmail = $AdUser.OtherMailbox
    [string]$FirstName = $AdUser.GivenName
    [string]$LastName = $Aduser.Surname
    [string]$Title = $AdUser.Title
    [string]$Department = $AdUser.Department
    [string]$EmployeeNumber = $AdUser.EmployeeNumber
    

    [string]$UserType = $Aduser.ExtensionAttribute1
    Write-host -ForegroundColor green "$Username : Usertype is $usertype"
    
    If (!($UserType)){ 
        write-host -ForegroundColor green "$username : Usertype is Null"
        If (($DN -like "*OU=student*") -or ($DN -like "*OU=Alumni*")){
            Write-host -ForegroundColor yellow "$Username : DN like student or alumni: $DN"
            $UserType = 'student'
        }
    }

    If ($UserType -ne 'student') {
    
        $OfficePhone = $Aduser.Office
        If ($null -eq $OfficePhone) { $OfficePhone = '0' }
        If (($null -eq $Department) -or ($Department -eq '')) {
            $Department = 'Other'
            Write-host "Department was Null changed to Other"}
        $WorkAddress = $AdUser.Office
    }
    
   
    else {
        $OfficePhone = '0'
        $WorkAddress = $Null
    }

    $Usercheck = Get-TDPersonByUsername -Username $Username #Verify if TD user Exists for this AD Account
    $d = get-date
    If ($UserCheck) { 

        If ($UserType -eq 'student') {
            write-host "$d  Running Function: Set-TDStudent to Update User $Username"
            Write-Output "$d  Running Function: Set-TDStudent to Update User $Username" | Out-File -FilePath $LogFile -Append
            $NewTDUser = Set-TDStudent -TDUser $UserCheck -Username $Username -FirstName $FirstName -LastName $LastName -email $Email -AlternateEmail $AlternateEmail -EmployeeNumber $EmployeeNumber  
        }
        Else {
            Write-host "$d  Running Function: Set-TDEmployee to Update User $Username"
            Write-Output "$d  Running Function: Set-TDEmployee to Update User $Username" | Out-File -FilePath $LogFile -Append
            $NewTDUser = Set-TDEmployee -TDuser $Usercheck -Username $Username -FirstName $FirstName -LastName $LastName -email $Email -AlternateEmail $AlternateEmail -OfficePhone $OfficePhone -WorkAddress $WorkAddress -EmployeeNumber $EmployeeNumber -Title $Title -Department $Department   
        }
    }
    Else {
        If ($UserType -eq 'student') {
            write-host "$d  Running Function: Add-TDStudent to Create User $Username" 
            Write-Output "$d  Running Function: Add-TDStudent to Create User $Username" | Out-File -FilePath $LogFile -Append
            $NewTDUser = Add-TDStudent -Username $Username -FirstName $FirstName -LastName $LastName -email $Email -AlternateEmail $AlternateEmail -EmployeeNumber $EmployeeNumber  
        }
        Else {
            write-host "$d  Running Function: Add-TDEmployee to Create User $Username"
            Write-Output "$d  Running Function: Add-TDEmployee to Create User $Username" | Out-File -FilePath $LogFile -Append
            $NewTDUser = Add-TDEmployee -Username $Username -FirstName $FirstName -LastName $LastName -email $Email -AlternateEmail $AlternateEmail -OfficePhone $OfficePhone -WorkAddress $WorkAddress -EmployeeNumber $EmployeeNumber -Title $Title -Department $Department   
        }
    }
    Return $NewTDUser
}

Function Add-TDDesktop {
    <#
    .SYNOPSIS
    When Passed the Guid ID of a Desktop template in TD along with a TD Person's UID This function can add the desktop template to the user in TD
    
    .DESCRIPTION
    Long description
    
    .PARAMETER DesktopID
    Guid of the Desktop Template in TD.  This can be extracted from the end of the URL string when looking at the Desktop in TD's Administration Page
    For Now Acadia Is only interested in the "Desktop-2020" Template
    
    .PARAMETER UserUids
    An Array of UUID Strings Collected by all operations Adding or updating users
    
    .PARAMETER isDefault
    Boolean value of $true or $false to determine if the Desktop Template will be applied as the default desktop for this Person in TDClient
    
    .EXAMPLE
    Add-TDDesktop -DesktopID "106cb4a4-9d16-4f7e-859f-4f2f897ef8a2" -UserUid "c7d1e2d4-0efb-eb11-b831-005056a06586" -isDefault $True
    
    .NOTES
    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    
    #>
    
    Param (
        [parameter(mandatory = $true)]
        [string]$DesktopID,
        [parameter(mandatory = $true)]
        [Array]$UserUids,
        [bool]$isDefault = $false
    )
    If ($IsDefault) {
        $IsDefault = 'true'
    }
    else { $IsDefault = 'false' }

    $body = $UserUids | ConvertTo-Json
    Write-Host -ForegroundColor Yellow $body
    $DesktopUri = "$tdURL/people/bulk/applydesktop/$DesktopID" + "?IsDefault=$IsDefault"
    Write-Host -ForegroundColor green $DesktopURI
    Invoke-RestMethod -Uri $DesktopUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $body -Headers $Global:headers
    
  
}

Function Get-TDUserGroupMembership {
    param(
        [parameter(mandatory=$true)]
        $TDUserUID
    )

    #https://app.teamdynamix.com/TDWebApi/api/groups/{id}/members 
    $Uri = "$tdURL/people/$TDUserUID/groups"
    $Groups = Invoke-RestMethod -Uri $Uri -ContentType $contentType -Method GET -UseBasicParsing -Headers $Global:headers
    
    #Sleep Due to API Rate Limiting
    start-sleep -Seconds 1
    return $Groups
}

Function Remove-TDGroupMember {
    <#
    .SYNOPSIS
    Add a Team Dynamix Person record to a Group. Optionaly this Group can be made the persons primary group.
          
    .PARAMETER GroupID
    A Numeric ID Number Associated with the Group.  Can be viewed in TD when looking at the group in the Admin interface
        
    .PARAMETER MemberUid
    The UID of a Person record in Team Dynamix that will be added to the Group
    
    .PARAMETER IsPrimary
    Boolean value of $true or $false that will indicate weather the group should become the users Primary Group
    
    .EXAMPLE
    Add-TDGroupMember -GroupID "13" -MemberUid "c7d1e2d4-0efb-eb11-b831-005056a06586" -IsPrimary $true
    
    .NOTES
    For Now Acadia is only interested with two groups (Students[12], and Employees[13]) So we have statically used these values
    In the future a another function to lookup group by name and extract the ID would be a good idea.

    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    #>

    Param(
        [parameter(mandatory = $true)]
        [string]$GroupID,
        [parameter(mandatory = $true)]
        [string]$MemberUid
    )

    $body = "[`"$MemberUid`"]"
    Write-Host -ForegroundColor Yellow $body
    $FeedUri = "$tdURL/groups/$GroupID/Members"
    Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method DELETE  -UseBasicParsing -Body $body -Headers $Global:headers

}

Function Add-TDGroupMember {
    <#
    .SYNOPSIS
    Add a Team Dynamix Person record to a Group. Optionaly this Group can be made the persons primary group.
          
    .PARAMETER GroupID
    A Numeric ID Number Associated with the Group.  Can be viewed in TD when looking at the group in the Admin interface
        
    .PARAMETER MemberUid
    The UID of a Person record in Team Dynamix that will be added to the Group
    
    .PARAMETER IsPrimary
    Boolean value of $true or $false that will indicate weather the group should become the users Primary Group
    
    .EXAMPLE
    Add-TDGroupMember -GroupID "13" -MemberUid "c7d1e2d4-0efb-eb11-b831-005056a06586" -IsPrimary $true
    
    .NOTES
    For Now Acadia is only interested with two groups (Students[12], and Employees[13]) So we have statically used these values
    In the future a another function to lookup group by name and extract the ID would be a good idea.

    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    #>

    Param(
        [parameter(mandatory = $true)]
        [string]$GroupID,
        [parameter(mandatory = $true)]
        [string]$MemberUid,
        [bool]$IsPrimary = $false
    )
        
    If ($ISPrimary) {
        $Primary = 'true'
        Remove-TDGroupMember -groupid $GroupID -MemberUid $MemberUid
    }
    else { $Primary = 'false' }

    $body = "[`"$MemberUid`"]"
    Write-Host -ForegroundColor Yellow $body
    $FeedUri = "$tdURL/groups/$GroupID/Members?isPrimary=$Primary"
    Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $body -Headers $Global:headers

}
Function Add-TDStudent {
    <#
    .SYNOPSIS
    Add A New Student Person to Team Dynamix, Set Students as their Primary Group and set "Desktop-2020" ad default desktop template.
      
    .PARAMETER Username
    AD Username - String
    
    .PARAMETER Email
    Users Internal Eamil Address
    
    .PARAMETER AlternateEmail
    Users External or Alternate Email Address
    
    .PARAMETER FirstName
    Users First Name
    
    .PARAMETER LastName
    Users Last Name
    
    .PARAMETER EmployeeNumber
    Users Employee Number from AD (Colleague Person ID)
    
    .EXAMPLE
    Add-TDStudent -Username "jdoe" -Email "5555555d@acmeinc.ca" -AlternateEmail "FuzzyFuzzyKitten@gmail.com" -FirstName 'John' -LastName 'Doe' -EmployeeNumber "5555555"
    
    .NOTES
    Typically Called from the Add-ADUser2TD function
    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    #>
    Param(
        $Username,
        $Email,
        $AlternateEmail,
        $FirstName,
        $LastName,
        $EmployeeNumber

    )
    #Append Username to Lastname so that Users can be searched by username in teamdynamix
    $LastName = "$LastName ($UserName)"
    
    #Static Info Unique to Your Institution
    $Company = 'ACME Inc.'
    $Title = 'Student'
    $IsEmployee = $false
    $WorkPhone = '0'
    $WorkZip = '90210'
    $DefaultAccountID = '77' #All Students are in the Student Account #Unique to Your Institution

    $SecurityRoleID = '74bbbbc-1220-ffff-aaaa-977770d5b321' #Basic User Role ID Unique to Your Institution
    

    
    $TDUser = New-Object -TypeName PSObject
    $TDUser | Add-Member -Type NoteProperty -Name 'Username' -Value $Username
    $TDUser | Add-Member -Type NoteProperty -Name 'FullName' -Value "$FirstName $LastName"
    $TDUser | Add-Member -Type NoteProperty -Name 'FirstName' -Value $FirstName
    $TDUser | Add-Member -Type NoteProperty -Name 'LastName' -Value $LastName
    $TDUser | Add-Member -Type NoteProperty -Name 'PrimaryEmail' -Value $Email
    $TDUser | Add-Member -Type NoteProperty -Name 'DefaultAccountID' -Value $DefaultAccountID
    $TDUser | Add-Member -Type NoteProperty -Name 'SecurityRoleID' -Value $SecurityRoleID
    $TDUser | Add-Member -Type NoteProperty -Name 'AlternateEmail' -Value $AlternateEmail
    $TDUser | Add-Member -Type NoteProperty -Name 'ExternalID' -Value $EmployeeNumber
    $TDUser | Add-Member -Type NoteProperty -Name 'AlternateID' -Value $EmployeeNumber
    $TDUser | Add-Member -Type NoteProperty -Name 'AlertEmail' -Value $Email
    $TDUser | Add-Member -Type NoteProperty -Name 'Company' -Value $Company
    $TDUser | Add-Member -Type NoteProperty -Name 'Title' -Value $Title
    $TDUser | Add-Member -Type NoteProperty -Name 'WorkPhone' -Value $WorkPhone
    $TDUser | Add-Member -Type NoteProperty -Name 'WorkZip' -Value $WorkZip
    $TDUser | Add-Member -Type NoteProperty -Name 'IsEmployee' -Value $IsEmployee
    $TDUser | Add-Member -Type NoteProperty -Name 'AuthenticationUserName' -Value $Username
    $TDUser | Add-Member -Type NoteProperty -Name 'TypeID' -Value '1'
    

    $UJson = $TDUser | ConvertTo-Json

    Write-Host $TDUser
    Write-Host $UJson
    $FeedUri = "$tdURL/people"
    $CreationResponse = Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $UJson -Headers $Global:headers
    Start-Sleep -Seconds 1

    $NewUID = $CreationResponse.UID
    Write-Host -ForegroundColor yellow "The New UID is: $NewUID"
    $StudentGroupID = '99' #Unique to Your Institution
    $d = get-date
    Write-Output "$d  Running Function: Add-ADGroupMember Adding $NewUID to Group $StudentGroupID as Primary" | Out-File -FilePath $LogFile -Append
    Add-TDGroupMember -GroupID $StudentGroupID -MemberUid $NewUID -IsPrimary $True 
    
    #Sleep Due to API Rate Limiting
    Start-Sleep -Seconds 1
    $Global:UUIDs += $NewID




}

Function Add-TDEmployee {
    <#
    .SYNOPSIS
    Add A New Employee Person to Team Dynamix, Set Employees as their Primary Group and set "Desktop-2020" ad default desktop template.
    
    .PARAMETER Username
    AD Username
    
    .PARAMETER Email
    Users Internal Eamil Address
    
    .PARAMETER AlternateEmail
    Users External or Alternate Email Address
    
    .PARAMETER FirstName
    Users First Name
    
    .PARAMETER LastName
    Users Last Name
    
    .PARAMETER EmployeeNumber
    Users Employee Number from AD (Colleague Person ID)

     .PARAMETER OfficePhone
    Office Phone number for the Employee
    
    .PARAMETER WorkAddress
    Typically the Building Code and office room number for the Employee
    
    .EXAMPLE
    Add-TDEmployee -Username "jdoe" -Email "john.doe@acmeinc.ca" -AlternateEmail "FuzzyFuzzyKitten@gmail.com" -FirstName 'John' -LastName 'Doe' -EmployeeNumber "5555555" -OfficePhone "(902)-585-1697" -WorkAddress "UHall 164"
    
    .NOTES
    Typically Called from the Add-ADUser2TD function
    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    
   
    
    #>
    Param(
        $Username,
        $Email,
        $AlternateEmail,
        $FirstName,
        $LastName,
        $Title,
        $Department,
        $EmployeeNumber,
        $OfficePhone,
        $WorkAddress,
        $headers

    )
    $LastName = "$LastName ($UserName)"
    $Company = 'ACME Inc.'
    $IsEmployee = $true
    #$WorkPhone = "0"
    $WorkZip = '90210'
    $SecurityRoleID = '745ee2dc-1910-ffff-aaaa-977770d5b321' #Basic User Role ID
    $DefaultAccountID = Get-TDAccountID -AccountName $Department 
    $EmployeeGroupID = '88' #Group ID for Employees from TD
       
    
    $TDUser = New-Object -TypeName PSObject
    $TDUser | Add-Member -Type NoteProperty -Name 'Username' -Value $Username
    $TDUser | Add-Member -Type NoteProperty -Name 'FullName' -Value "$FirstName $LastName"
    $TDUser | Add-Member -Type NoteProperty -Name 'FirstName' -Value $FirstName
    $TDUser | Add-Member -Type NoteProperty -Name 'LastName' -Value $LastName
    $TDUser | Add-Member -Type NoteProperty -Name 'PrimaryEmail' -Value $Email
    $TDUser | Add-Member -Type NoteProperty -Name 'DefaultAccountID' -Value $DefaultAccountID
    $TDUser | Add-Member -Type NoteProperty -Name 'SecurityRoleID' -Value $SecurityRoleID
    $TDUser | Add-Member -Type NoteProperty -Name 'AlternateEmail' -Value $AlternateEmail
    $TDUser | Add-Member -Type NoteProperty -Name 'ExternalID' -Value $EmployeeNumber
    $TDUser | Add-Member -Type NoteProperty -Name 'AlternateID' -Value $EmployeeNumber
    $TDUser | Add-Member -Type NoteProperty -Name 'AlertEmail' -Value $Email
    $TDUser | Add-Member -Type NoteProperty -Name 'Company' -Value $Company
    $TDUser | Add-Member -Type NoteProperty -Name 'Title' -Value $Title
    $TDUser | Add-Member -Type NoteProperty -Name 'WorkPhone' -Value $OfficePhone
    $TDUser | Add-Member -Type NoteProperty -Name 'WorkAddress' -Value $WorkAddress
    $TDUser | Add-Member -Type NoteProperty -Name 'WorkZip' -Value $WorkZip
    $TDUser | Add-Member -Type NoteProperty -Name 'IsEmployee' -Value $IsEmployee
    $TDUser | Add-Member -Type NoteProperty -Name 'AuthenticationUserName' -Value $Username
    $TDUser | Add-Member -Type NoteProperty -Name 'TypeID' -Value '1'
    

    $UJson = $TDUser | ConvertTo-Json

    Write-Host $TDUser
    Write-Host $UJson
    $FeedUri = "$tdURL/people"
    $CreationResponse = Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $UJson -Headers $Global:headers
    Start-Sleep -Seconds 1

    $NewUID = $CreationResponse.UID
    Write-Host -ForegroundColor yellow "The User UID is: $NewUID"
   
    #Add User to Employees Group
    $d = get-date
    Write-Output "$d  Running Function: Add-TDGroupMember Adding $NewUID to Group $EmployeeGroupID as Primary" | Out-File -FilePath $LogFile -Append
    Add-TDGroupMember -GroupID $EmployeeGroupID -MemberUid $NewUID -IsPrimary $True 
    
    #Sleep Due to API Rate Limiting
    Start-Sleep -Seconds 1
   
    $Global:UUIDs += $NewID

  
}

Function Set-TDStudent {
    <#
    .SYNOPSIS
    Updates an existing Student Person In Team Dynamix, Set Students as their Primary Group and set "Desktop-2020" ad default desktop template.
    
    .PARAMETER TDUser
    A Powershell object return by Get-TDPersonByUsername 
    Will be updated, converted to json and then posted back to Team Dynamix
    
    .PARAMETER Username
    AD Username - String
    
    .PARAMETER Email
    Users Internal Eamil Address
    
    .PARAMETER AlternateEmail
    Users External or Alternate Email Address
    
    .PARAMETER FirstName
    Users First Name
    
    .PARAMETER LastName
    Users Last Name
    
    .PARAMETER EmployeeNumber
    Users Employee Number from AD (Colleague Person ID)
    
    .EXAMPLE
    $AdUser = Get-TDPersonByUsername -Username 'jdoe'
    Set-TDStudent -TDUser $TDuser -Username "jdoe" -Email "5555555d@acmeinc.ca" -AlternateEmail "FuzzyFuzzyKitten@gmail.com" -FirstName 'John' -LastName 'Doe' -EmployeeNumber "5555555"
    
    .NOTES
    Typically Called from the Add-ADUser2TD function
    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    #>
    Param(
        $TDUser,
        $Username,
        $Email,
        $AlternateEmail,
        $FirstName,
        $LastName,
        $EmployeeNumber,
        $headers

    )
    #Append Username to Lastname so that Users can be searched by username in teamdynamix
    $LastName = "$LastName ($UserName)"
    
    #Static Info Unique to Your Institution
    $Company = 'ACME Inc.'
    $Title = 'Student'
    $IsEmployee = $false
    $WorkPhone = '0'
    $WorkZip = '90210'
    $DefaultAccountID = '77' #All Students are in the Student Account
    
    $TDUserUID = $TDUser.UID

        
    $TDUser.Username = $Username
    $TDUser.FullName = "$FirstName $LastName"
    $TDUser.FirstName = $FirstName
    $TDUser.LastName = $LastName
    $TDUser.PrimaryEmail = $Email
    $TDUser.DefaultAccountID = $DefaultAccountID
    $TDUser.AlternateEmail = $AlternateEmail
    $TDUser.ExternalID = $EmployeeNumber
    $TDUser.AlternateID = $EmployeeNumber
    $TDUser.AlertEmail = $Email
    $TDUser.Company = $Company
    $TDUser.Title = $Title
    $TDUser.WorkPhone = $WorkPhone
    $TDUser.WorkZip = $WorkZip
    $TDUser.IsEmployee = $IsEmployee
    $TDUser.AuthenticationUserName = $Username
    $TDUser.TypeID = '1'
    
    $UJson = $TDUser | ConvertTo-Json

    #Write-Host $TDUser
    #Write-Host $UJson
    $FeedUri = "$tdURL/people/$TDUserUID"
    $CreationResponse = Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $UJson -Headers $Global:headers
    
    #Sleep Due to API Rate Limiting
    Start-Sleep -Seconds 1

    $NewUID = $CreationResponse.UID
    Write-Host -ForegroundColor yellow "The User UID is: $NewUID"
    $StudentGroupID = '99' #Unique to Your Institution
    $d = get-date
   
    #Examine Existing TD Group Memberships

    $TDGroups = Get-TDUserGroupMembership -TDUserUID $TDUserUID
    $PrimaryTDGroup = $TDGroups | Where-object {$_.isPrimary -eq 'True'} # Check to validate f the Student Group is alreay primary
   
    If (($TDGroups.GroupID -Contains $StudentGroupID) -And ($PrimaryTDGroup.GroupID -eq $StudentGroupID)){
        Write-Output "$d  $Username ($NewUID) Already a Member of Group $StudentGroupID as Primary" | Out-File -FilePath $LogFile -Append
    }
    ElseIF (($TDGroups.GroupID -Contains $StudentGroupID) -and ($PrimaryTDGroup.GroupID -ne $StudentGroupID) -And ($PrimaryTDGroup)){
            Write-Output "$d  $Username ($NewUID) Already a Member of Group $StudentGroupID NOT Primary -Leaving Unchanged" | Out-File -FilePath $LogFile -Append
        }
    Elseif (!($PrimaryTDGroup) -And ($TDGroups.GroupID -Contains $StudentGroupID)){
        #Remove then add as primary
        Write-Output "$d  Running Function: Remove-TDGroupMember Remove $NewUID From Group $StudentGroupID So They can be re-added as Primary" | Out-File -FilePath $LogFile -Append
        Remove-TDGroupMember -GroupID $StudentGroupID -MemberUid $NewUID 
        Write-Output "$d  Running Function: Add-TDGroupMember Adding $NewUID to Group $StudentGroupID as Primary" | Out-File -FilePath $LogFile -Append
        Add-TDGroupMember -GroupID $StudentGroupID -MemberUid $NewUID -IsPrimary $True 
    }
    Elseif (!($PrimaryTDGroup) -And ($TDGroups.GroupID -NotContains $StudentGroupID)){
        #Add as Primary
        Write-Output "$d  Running Function: Add-TDGroupMember Adding $NewUID to Group $StudentGroupID as Primary" | Out-File -FilePath $LogFile -Append
        Add-TDGroupMember -GroupID $StudentGroupID -MemberUid $NewUID -IsPrimary $True 
    
    }
    Elseif(($PrimaryTDGroup) -And ($TDGroups.GroupID -NotContains $StudentGroupID)){
        #Add Not as Primary
        Write-Output "$d  Running Function: Add-TDGroupMember Adding $NewUID to Group $StudentGroupID But Leaving Existing Primary Group Unchanged" | Out-File -FilePath $LogFile -Append
        Add-TDGroupMember -GroupID $StudentGroupID -MemberUid $NewUID -IsPrimary $False 
    
    }
    
    
    #Sleep Due to API Rate Limiting
    Start-Sleep -Seconds 1
    $Global:UUIDs += $NewID
   



}
Function Set-TDEmployee {
    <#
    .SYNOPSIS
    Updates an existing Employee Person to Team Dynamix, Set Employees as their Primary Group and set "Desktop-2020" ad default desktop template.
    
    .PARAMETER TDUser
    A Powershell object return by Get-TDPersonByUsername 
    Will be updated, converted to json and then posted back to Team Dynamix

    .PARAMETER Username
    AD Username
    
    .PARAMETER Email
    Users Internal Eamil Address
    
    .PARAMETER AlternateEmail
    Users External or Alternate Email Address
    
    .PARAMETER FirstName
    Users First Name
    
    .PARAMETER LastName
    Users Last Name
    
    .PARAMETER EmployeeNumber
    Users Employee Number from AD (Colleague Person ID)

     .PARAMETER OfficePhone
    Office Phone number for the Employee
    
    .PARAMETER WorkAddress
    Typically the Building Code and office room number for the Employee
    
    .EXAMPLE
    $TDUser = Get-TDPersonByUsername -username 'jdoe'
    Add-TDEmployee -Username "jdoe" -Email "john.doe@acmeinc.ca" -AlternateEmail "FuzzyFuzzyKitten@gmail.com" -FirstName 'John' -LastName 'Doe' -EmployeeNumber "5555555" -OfficePhone "(902)-585-1697" -WorkAddress "UHall 164"
    
    .NOTES
    Typically Called from the Add-ADUser2TD function
    Requires a Global Variable $headers which contains a bearer token authorizing access to the TD API
    ex: $Global:headers = @{Authorization = "Bearer $bearer_token"}
    #>
    Param(
        
        $TDUser,
        $Username,
        $Email,
        $AlternateEmail,
        $FirstName,
        $LastName,
        $Title,
        $Department,
        $EmployeeNumber,
        $OfficePhone,
        $WorkAddress,
        $headers

    )
    $LastName = "$LastName ($UserName)"
    $Company = 'ACME Inc.'
    $IsEmployee = $true
    #$WorkPhone = "0"
    $WorkZip = '90210'
    $DefaultAccountID = Get-TDAccountID -AccountName $Department 
    $EmployeeGroupID = '88' #Unique to Your Institution
    $TDUserUID = $TDUser.UID
    
    #$TDUser = New-Object -TypeName PSObject
    $TDUser.Username = $Username
    $TDUser.FullName = "$FirstName $LastName"
    $TDUser.FirstName = $FirstName
    $TDUser.LastName = $LastName
    $TDUser.PrimaryEmail = $Email
    $TDUser.DefaultAccountID = $DefaultAccountID
    $TDUser.AlternateEmail = $AlternateEmail
    $TDUser.ExternalID = $EmployeeNumber
    $TDUser.AlternateID = $EmployeeNumber
    $TDUser.AlertEmail = $Email
    $TDUser.Company = $Company
    $TDUser.Title = $Title
    $TDUser.WorkPhone = $OfficePhone
    $TDUser.WorkAddress = $WorkAddress
    $TDUser.WorkZip = $WorkZip
    $TDUser.IsEmployee = $IsEmployee
    $TDUser.AuthenticationUserName = $Username
    $TDUser.TypeID = '1'
    

    $UJson = $TDUser | ConvertTo-Json

    Write-Host $TDUser
    Write-Host $UJson
    $FeedUri = "$tdURL/people/$TDUserUID"
    $CreationResponse = Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $UJson -Headers $Global:headers
    
    #Sleep Due to API Rate Limiting
    Start-Sleep -Seconds 1

    $NewUID = $CreationResponse.UID
    Write-Host -ForegroundColor yellow "The New UID is: $NewUID"
   
    #Add User to Employees Group
    $d = get-date
   
     #Examine Existing TD Group Memberships

    $TDGroups = Get-TDUserGroupMembership -TDUserUID $TDUserUID
    $PrimaryTDGroup = $TDGroups | Where-object {$_.isPrimary -eq 'True'} 

    If (($TDGroups.GroupID -Contains $EmployeeGroupID) -And ($PrimaryTDGroup.GroupID -eq $EmployeeGroupID)){
        Write-Output "$d  $Username ($NewUID) Already a Member of Group $EmployeeGroupID as Primary" | Out-File -FilePath $LogFile -Append
    }
    ElseIF (($TDGroups.GroupID -Contains $EmployeeGroupID) -and ($PrimaryTDGroup.GroupID -ne $EmployeeGroupID) -And ($PrimaryTDGroup)){
        Write-Output "$d  $Username ($TDUserUID) Already a Member of Group $EmployeeGroupID NOT Primary -Leaving Unchanged" | Out-File -FilePath $LogFile -Append
        }
    Elseif (!($PrimaryTDGroup) -And ($TDGroups.GroupID -Contains $EmployeeGroupID)){
        #Remove then add as primary
        Write-Output "$d  Running Function: Remove-TDGroupMember Remove $TDUserUID From Group $EmployeeGroupID So They can be re-added as Primary" | Out-File -FilePath $LogFile -Append
        Remove-TDGroupMember -GroupID $EmployeeGroupID -MemberUid $TDUserUID 
        Write-Output "$d  Running Function: Add-TDGroupMember Adding $TDUserUID to Group $EmployeeGroupID as Primary" | Out-File -FilePath $LogFile -Append
        Add-TDGroupMember -GroupID $EmployeeGroupID -MemberUid $TDUserUID -IsPrimary $True 
    }
    Elseif (!($PrimaryTDGroup) -And ($TDGroups.GroupID -NotContains $EmployeeGroupID)){
        #Add as Primary
        Write-Output "$d  Running Function: Add-TDGroupMember Adding $TDUserUID to Group $EmployeeGroupID as Primary" | Out-File -FilePath $LogFile -Append
        Add-TDGroupMember -GroupID $EmployeeGroupID -MemberUid $TDUserUID -IsPrimary $True 
    }
    Elseif(($PrimaryTDGroup) -And ($TDGroups.GroupID -NotContains $EmployeeGroupID)){
        #Add Not as Primary
        Write-Output "$d  Running Function: Add-TDGroupMember Adding $TDUserUID to Group $EmployeeGroupID But Leaving Existing Primary Group Unchanged" | Out-File -FilePath $LogFile -Append
        Add-TDGroupMember -GroupID $EmployeeGroupID -MemberUid $TDUserUID -IsPrimary $False 
    }
    
    #Sleep Due to API Rate Limiting
    Start-Sleep -Seconds 1
    $Global:UUIDs += $NewID    
  


}
##
Function Get-AdminBearer {
    <#
    .SYNOPSIS
    Authenticates with Admin API endpoint and returns Bearer token good for 24 hours.  Uses Global Variables to populate BEID and WebServicesKey
        
    .EXAMPLE
    $AdminBearer = Get-AdminBearer
    
    .NOTES
    This is Required when working with People etc from the API a normal service user Bearer Token will not provide
    sufficient access.
    #>

    $url = $tdURL
    $action = '/auth/loginadmin'
    $endpoint = $url + $action

    $request = "{
    `"BEID`": `"$Global:BEID`",
    `"WebServicesKey`": `"$Global:WebServicesID`"
}"

    $Bearer = Invoke-RestMethod -Method Post -Uri $endpoint -Body $request -ContentType 'application/json; charset=utf-8'

    return $Bearer

}

Function Get-TDAccountID {
    <#
    .SYNOPSIS
    Returns the Guid ID of a Department/Account in Team Dynamix from the Department/Account Name passed as AccountName parameter
     
    .PARAMETER AccountName
    String Value Department Name
    
    .EXAMPLE
    Get-TDAccountID -AccountName "Technology Services"
    
    .NOTES
    Used by add-TDEmployee and Set-TDEmployee to add the default acct/dept based on the department field in AD
    #>
    param (
        [parameter(mandatory=$true)]
        $AccountName
    )
    $AccountSearchURI = $tdURL + '/accounts/search'
    
    $body = New-Object -TypeName PSObject
    $body | Add-Member -Type NoteProperty -Name 'SearchText' -Value $AccountName
    $jbody = $body | ConvertTo-Json

    Write-Host $body
    Write-Host -ForegroundColor yellow $jbody
    $Account = Invoke-RestMethod -Uri $AccountSearchURI -ContentType $contentType -Method POST  -UseBasicParsing -Body $jbody -Headers $Global:headers
    
    return $Account.ID
}
Function Get-TDPersonByUsername {
    <#
    .SYNOPSIS
    Returns a User Object from TD Based on the Username passed as a parameter
    
    .PARAMETER Username
    Username of the person object being looked update
    
    .EXAMPLE
    Get-TDPersonByUsername -Username 'RRabbit'
    
    .NOTES
    Used by Add-ADUser2TD function to determine if user already exists and to pass the user object to Set-TDEmployee or Set-TDStudent
    #>
    param(
        [parameter(Mandatory=$true)]
        [string] $Username
    )
    $Update = "{`"username`": `"$Username`"}"
    $FeedUri = "$tdURL/people/search"
    $SearchResponse = Invoke-RestMethod -Uri $FeedUri -ContentType $contentType -Method POST  -UseBasicParsing -Body $Update -Headers $Global:headers
    # Inject sleep statement to prevent API throttling
    start-sleep -Milliseconds 500
    # Return Full User Attributes: https://app.teamdynamix.com/TDWebApi/api/people/{uid}
    
    If ($SearchResponse){
    #Search returns limited attributes Getting users full attribute set and returning it.
    [string]$Uid = $SearchResponse.uid
    Write-host -ForegroundColor Yellow "Collecting Full Attributes from TD for User ID: $Uid"
    $PeopleURI = "$tdURL/people/$Uid"
    $fullUser = Invoke-RestMethod -Uri $PeopleUri -ContentType $contentType -Method GET  -UseBasicParsing -Headers $Global:headers
     # Inject sleep statement to prevent API throttling
    start-sleep -Milliseconds 500
    Return $fullUser
    }
}

Function Get-BearerToken {
    <#
    .SYNOPSIS
    Authenticates a user account and returns a bearer token to be used with the API representing that user
    
    .PARAMETER User
    String Username
    
    .PARAMETER Password
    String Password
    
    .EXAMPLE
    get-bearertoken -username "ServiceAcct" -Password "SuperSecretPassword"
    
    .NOTES
    Can not be used with all admin functions such as Managing people.
    #>
    param(
        [parameter(mandatory=$true)]
        [String] $User,
        [parameter(mandatory=$true)]
        [string] $Password
    )
    #Get Credentials if not passed as params
    If (($null -eq $User) -Or ($null -eq $Password)) {
        $credin = Get-Credential
        $User = $credin.UserName
        $Password = $credin.GetNetworkCredential().password
    }
    #Json Body to pass to API to obtain bearer Token
    $body = "{username: '$User', password: '$Password'}"
    $TokenRequest = Invoke-RestMethod -UseBasicParsing -Uri "$tdURL/auth" -ContentType $contentType -Method POST -Body $body -Headers $Global:headers
    return $TokenRequest    

}
#Add the following to Script to get bearer token for API integration..  Working with some aspects like people require an admin bearer_token

#$bearer_token = Get-BearerToken -User "$un" -Password $pw
$bearer_token = Get-AdminBearer
#Generate headers with Bearer Token to be used in all API related functions
$Global:headers = @{Authorization = "Bearer $bearer_token" }

