variable "project_name" {
  description = "Prefijo de nombres (para recursos AWS)"
  type        = string
  default     = "dtapia-queso"
}

variable "node_name_prefix" {
  description = "Prefijo para las instancias (Name tag)"
  type        = string
  default     = "quesotapia"
}

variable "region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo de instancia"
  type        = string
  default     = "t2.micro"
}

variable "docker_images" {
  description = "Imágenes Docker (una por instancia)"
  type        = list(string)
  default     = [
    "errm/cheese:wensleydale",
    "errm/cheese:cheddar",
    "errm/cheese:stilton"
  ]
}

variable "allow_ssh" {
  description = "Si true, abre SSH 22 únicamente a tu IP"
  type        = bool
  default     = false
}

variable "ssh_cidr_override" {
  description = "CIDR manual para SSH (opcional; deja vacío para auto-IP)"
  type        = string
  default     = ""
}

# Diagnóstico: permite HTTP directo a EC2 sólo desde tu IP (mejor dejar en false)
variable "diag_open_http" {
  type    = bool
  default = false
}
