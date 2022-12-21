Import-Module WindowsForms

# Create the main form
$form = New-Object Windows.Forms.Form
$form.Text = "Power Compare"
$form.Size = New-Object Drawing.Size @(1000,600)

# Create the "Folder 1" label
$folder1Label = New-Object Windows.Forms.Label
$folder1Label.Text = "Folder 1:"
$folder1Label.Size = New-Object Drawing.Size @(50,25)
$folder1Label.Location = New-Object Drawing.Point @(50,50)

# Add the "Folder 1" label to the form
$form.Controls.Add($folder1Label)

# Create the "Folder 1" text box
$folder1TextBox = New-Object Windows.Forms.TextBox
$folder1TextBox.Size = New-Object Drawing.Size @(250,25)
$folder1TextBox.Location = New-Object Drawing.Point @(105,50)

# Add the "Folder 1" text box to the form
$form.Controls.Add($folder1TextBox)

# Create the "Browse" button for the "Folder 1" text box
$browseButton1 = New-Object Windows.Forms.Button
$browseButton1.Text = "Browse"
$browseButton1.Size = New-Object Drawing.Size @(100,25)
$browseButton1.Location = New-Object Drawing.Point @(360,50)
$browseButton1.Name = "browseButton1"

# Add the "Browse" button to the form
$form.Controls.Add($browseButton1)

# Specify the action to be taken when the "Browse" button is clicked
$browseButton1.Add_Click({
    # Show the "Open Folder" dialog
    $folderBrowserDialog = New-Object Windows.Forms.FolderBrowserDialog
    $result = $folderBrowserDialog.ShowDialog()
    
    # If a folder was selected, update the appropriate text box
    if ($result -eq [System.Windows.Forms.DialogResult]::OK)
    {
        # Determine which text box to update based on the button that was clicked
        if ($browseButton1.Name -eq "browseButton1")
        {
            $folder1TextBox.Text = $folderBrowserDialog.SelectedPath
        }
        else
        {
            $folder2TextBox.Text = $folderBrowserDialog.SelectedPath
        }
    }
})

# Create the "Folder 2" label
$folder2Label = New-Object Windows.Forms.Label
$folder2Label.Text = "Folder 2:"
$folder2Label.Size = New-Object Drawing.Size @(50,25)
$folder2Label.Location = New-Object Drawing.Point @(470,50)

# Add the "Folder 2" label to the form
$form.Controls.Add($folder2Label)

# Create the "Folder 2" text box
$folder2TextBox = New-Object Windows.Forms.TextBox
$folder2TextBox.Size = New-Object Drawing.Size @(250,25)
$folder2TextBox.Location = New-Object Drawing.Point @(525,50)

# Add the "Folder 2" text box to the form
$form.Controls.Add($folder2TextBox)

# Create the "Browse" button for the "Folder 2" text box
$browseButton2 = New-Object Windows.Forms.Button
$browseButton2.Text = "Browse"
$browseButton2.Size = New-Object Drawing.Size @(100,25)
$browseButton2.Location = New-Object Drawing.Point @(780,50)
$browseButton2.Name = "browseButton2"

# Add the "Browse" button to the form
$form.Controls.Add($browseButton2)

# Specify the action to be taken when the "Browse" button is clicked
$browseButton2.Add_Click({
    # Show the "Open Folder" dialog
    $folderBrowserDialog = New-Object Windows.Forms.FolderBrowserDialog
    $result = $folderBrowserDialog.ShowDialog()
    
    # If a folder was selected, update the appropriate text box
    if ($result -eq [System.Windows.Forms.DialogResult]::OK)
    {
        # Determine which text box to update based on the button that was clicked
        if ($browseButton2.Name -eq "browseButton1")
        {
            $folder1TextBox.Text = $folderBrowserDialog.SelectedPath
        }
        else
        {
            $folder2TextBox.Text = $folderBrowserDialog.SelectedPath
        }
    }
})

# Create the "Compare" button
$compareButton = New-Object Windows.Forms.Button
$compareButton.Text = "Compare"
$compareButton.Size = New-Object Drawing.Size @(100,25)
$compareButton.Location = New-Object Drawing.Point @(50,100)

# Add the "Compare" button to the form
$form.Controls.Add($compareButton)

# Specify the action to be taken when the "Compare" button is clicked
$compareButton.Add_Click({
    # Get the paths of the selected folders
    $folder1 = $folder1TextBox.Text
    $folder2 = $folder2TextBox.Text
    
    # Compare the selected folders
    $differences = Compare-Object (Get-ChildItem $folder1) (Get-ChildItem $folder2)

    # Display the differences in a list view
    $listView = New-Object Windows.Forms.ListView
    $listView.Size = New-Object Drawing.Size @(750,400)
    $listView.Location = New-Object Drawing.Point @(25,150)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true

    # Add columns to the list view
    $listView.Columns.Add("Name", 200, [System.Windows.Forms.HorizontalAlignment]::Left)
    $listView.Columns.Add("Type", 50, [System.Windows.Forms.HorizontalAlignment]::Left)
    $listView.Columns.Add("Folder 1", 200, [System.Windows.Forms.HorizontalAlignment]::Left)
    $listView.Columns.Add("Folder 2", 200, [System.Windows.Forms.HorizontalAlignment]::Left)
    $listView.Columns.Add("Result", 100, [System.Windows.Forms.HorizontalAlignment]::Left)

    # Add items to the list view
    foreach ($difference in $differences)
    {
        # Create a new list view item
        $item = New-Object Windows.Forms.ListViewItem

        # Set the item's properties
        $item.Text = $difference.InputObject.Name
        if ($difference.InputObject.PSIsContainer)
        {
            $item.SubItems.Add("Folder")
        }
        else
        {
            $item.SubItems.Add("File")
        }
        $item.SubItems.Add($difference.InputObject.FullName)
        if ($difference.SideIndicator -eq "=>")
        {
            $item.SubItems.Add("")
            $item.SubItems.Add("Only in Folder 2")
        }
        else
        {
            $item.SubItems.Add("Only in Folder 1")
            $item.SubItems.Add("")
        }

        # Add the item to the list view
        $listView.Items.Add($item)
    }

    # Add the list view to the form
    $form.Controls.Add($listView)
})

# Display the form
$form.ShowDialog()

