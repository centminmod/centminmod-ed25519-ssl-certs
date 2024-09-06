#!/bin/bash

# Default expiry set to 10 years if not specified by the user
expiry_years=10

# Parse command line arguments using getopts:
# -d: Comma-separated list of domains (e.g., domain.com,www.domain.com)
# -e: Expiry in years (optional, default is 10 years)
# -p: Path to where the certificate, key, and CSR will be saved
while getopts "d:e:p:" opt; do
  case $opt in
    d) domain_list=$OPTARG ;;    # Store the domain list provided by the user
    e) expiry_years=$OPTARG ;;   # Store the expiry years provided by the user
    p) output_path=$OPTARG ;;    # Store the output path provided by the user
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;; # Error message for invalid options
  esac
done

# Ensure the domain list (-d) is provided. If not, display usage information and exit.
if [ -z "$domain_list" ]; then
  echo "Usage: $0 -d domain.com,www.domain.com,sub.domain.com [-e expiry_years] [-p /path/to/save]"
  exit 1
fi

# Convert the provided expiry years to days (since OpenSSL uses days for certificate expiry)
expiry_days=$((expiry_years * 365))

# Set the primary domain to the first entry in the comma-separated list (this will be the CN)
primary_domain=$(echo "$domain_list" | cut -d',' -f1)

# Ensure the output path is set, if not provided, default to the current directory
if [ -z "$output_path" ]; then
  output_path="./"
fi

# Ensure the output path ends with a trailing slash (to ensure proper file path creation)
output_path="${output_path%/}/"

# Create a subdirectory in the output path based on the primary domain
domain_dir="${output_path}ed25519-${primary_domain}/"

# Ensure the subdirectory exists
mkdir -p "$domain_dir"

# Create the prefix for file names based on the primary domain
# Example: If primary domain is domain.com, files will be saved as ed25519-domain.com/domain.com.key, .csr, .crt
file_prefix="${domain_dir}${primary_domain}"

# Convert the comma-separated domain list into a space-separated list (for easier looping)
san_list=$(echo "$domain_list" | sed 's/,/ /g')

# Generate the CSR configuration file dynamically using a heredoc
# This file will contain the Common Name (CN) and Subject Alternative Names (SANs)
cat > csr.conf <<EOF
[ req ]
prompt = no
distinguished_name = dn
req_extensions = req_ext

[ dn ]
CN = $primary_domain   # Common Name (the first domain in the list)

[ req_ext ]
subjectAltName = @alt_names  # Reference the SAN section

[ alt_names ]
EOF

# Loop through the space-separated domain list and add each domain to the alt_names section
count=1
for domain in $san_list; do
  echo "DNS.$count = $domain" >> csr.conf  # Append each domain as DNS.# to csr.conf
  count=$((count + 1))  # Increment the DNS count
done

# Generate the certificate configuration file dynamically using a heredoc
# This file is used when generating the self-signed certificate with the subject alternative names
cat > cert.conf <<EOF
[ v3_ca ]
subjectAltName = @alt_names  # SAN section for the certificate

[ alt_names ]
EOF

# Again, loop through the domain list and add each domain to the SANs in the certificate configuration
count=1
for domain in $san_list; do
  echo "DNS.$count = $domain" >> cert.conf  # Append each domain as DNS.# to cert.conf
  count=$((count + 1))  # Increment the DNS count
done

# Generate the Ed25519 private key using OpenSSL
openssl genpkey -algorithm ED25519 -out "${file_prefix}.key"

# Generate the CSR using the private key and the dynamically created CSR configuration file
openssl req -new -key "${file_prefix}.key" -out "${file_prefix}.csr" -config csr.conf

# Generate the self-signed SSL certificate with the specified expiry (in days)
# The certificate uses the CSR and the private key, and includes the SANs from the cert.conf file
openssl x509 -req -in "${file_prefix}.csr" -signkey "${file_prefix}.key" -out "${file_prefix}.crt" -days "$expiry_days" -extfile cert.conf -extensions v3_ca

# Clean up the temporary configuration files used for CSR and certificate generation
rm csr.conf cert.conf

# Output the paths of the generated files to the user
echo "Self-signed certificate and private key have been generated and saved to ${domain_dir}:"
echo
echo "Private Key: ${file_prefix}.key"
echo "Certificate: ${file_prefix}.crt"
echo "CSR: ${file_prefix}.csr"

# Display the Nginx configuration lines with the actual paths
echo
echo "To use these in your Nginx configuration, add the following lines:"
echo
echo "   ssl_certificate ${file_prefix}.crt;"
echo "   ssl_certificate_key ${file_prefix}.key;"

# Inspect the generated certificate and display details
echo
echo "Here are the details of the generated certificate:"
openssl x509 -in "${file_prefix}.crt" -text -noout
