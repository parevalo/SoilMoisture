# We aim to fuse Times-Series Data in a State Space Model: SMAP, GMP and MODIS

# In this test, soilmoisture is a SoilMoisturePrecipFusion model

###################
#------------------ sub-routines,set your JAGS model here
predict.JAGS <- function(time,y,p,t,v,NA.indices) {
  require(rjags)
  require(coda)
  
  SoilMoisturePrecipFusion = "
  model{
  
  #### Data Model
  for(t in 1:nt){
  y[t] ~ dnorm(x[t],tau_obs)
  }

  
  #### Process Model
  for(t in 2:nt){
  SoilMoisture[t] <- beta_0*x[t-1] + beta_1*p[t-1] + beta_2*n[t]
  #Term 1: runoff
  #Term 2: Added impact from yesterday's rainfall (assuming 1 day delay)
  #Term 3: Effect of NDVI
  x[t]~dnorm(SoilMoisture[t],tau_add)
  }

  for(t in 1:length(NA.indices)){
  p[NA.indices[t]] ~ dlnorm(5, 1)
  }
  

  
  #### Priors
  tau_obs ~ dgamma(a_obs,r_obs)
  tau_add ~ dgamma(a_add,r_add)
  beta_0 ~ dbeta(a_beta0,r_beta0)
  beta_1 ~ dgamma(a_beta1,r_beta1)
  beta_2 ~ dbeta(a_beta2,r_beta2)
  tau_ind ~ dgamma(0.01,0.01)
  mu_p ~ dnorm(mu_p0, tau_p0)
  tau_p ~ dgamma(.01, .01)

  ## initial condition
  x[1] ~ dunif(x_ic_lower,x_ic_upper)  
  }
  "
  
  data <- list(y=log(y),p=p, n=n, NA.indices=NA.indices, nt=length(y),x_ic_lower=log(0.000001),x_ic_upper=log(1), a_obs=0.01,
               r_obs=0.01,a_add=0.01, r_add=.01, a_beta0=1,r_beta0=0.5, a_beta1=2, r_beta1=2,
               a_beta2=.05,r_beta2=9, mu_p0=3, tau_p0=3,a_p=1,r_p=1)

  
  nchain = 3
  init <- list()
  for(i in 1:nchain){
    y.samp = sample(y,length(y),replace=TRUE)
    init[[i]] <- list(tau_add=1/var(diff((log(y.samp)))),tau_obs=1/var((log(y.samp))), 
                      ind=rep(0,length(y)), tau_ind=0.01)
  }
  
  j.model   <- jags.model (file = textConnection(SoilMoisturePrecipFusion),
                           data = data,
                           inits = init,
                           n.chains = 3)
  
  ## burn-in
  jags.out   <- coda.samples (model = j.model,
                              variable.names = c("tau_add","tau_obs","beta_0","beta_1","beta_2","tau_ind"),
                              n.iter = 1000)
  # Only to plot 1000 iterations.  
  
  plot(jags.out) 
  
  
  jags.out   <- coda.samples (model = j.model,
                              variable.names = c("x","tau_add","tau_obs","beta_0","beta_1","beta_2","tau_ind"),
                              n.iter = 10000)
  
  #summary of the final 10000 iteration jags.out
  #summary(jags.out)
  
}

#-------------plots a confidence interval around an x-y plot (e.g. a timeseries)
ciEnvelope <- function(x,ylo,yhi,...){
  polygon(cbind(c(x, rev(x), x[1]), c(ylo, rev(yhi),ylo[1])), border = NA,...) 
}


#-------------load data from combined csv
## set working directory 
data.root.path = '/Users/ericbullock/Google Drive/Class/Ecological_Forecasting/Project/SoilMoisture/example/'
#data.root.path = 'C:/Users/condo/Documents/SoilMoisture/example/'
# Soil Moisture (cm^3 of water per cm^3 of soil)
combined <- as.data.frame(read.csv(sprintf("%scombined_data.csv",data.root.path)))
combined<-combined[0:55,]
#remove NA values
require(zoo)
#interpolate between values keeping NA
combined$NDVI<-na.approx(combined$NDVI,na.rm=FALSE)    #reset
#apply last available to NA values
combined$NDVI<-na.locf(combined$NDVI,na.rm=FALSE)   
combined<-combined[!(is.na(combined$NDVI) | combined$NDVI==""), ]    #remove NA values at beginning



#-------------Run JAGS, and Do some plots
time = as.Date(combined$Date)
y = combined$SoilMoisture
p = combined$Precip
p[0:5] <- NA
NA.indices <- which(is.na(p))
n = combined$NDVI


# plot original weekly observation data
plot(time,y,type='l',ylab="SoilMoisture",lwd=2,main='Daily SoilMoisture', ,ylim=c(0,.6))

jags.out.original = predict.JAGS(time,y, p,t,n,NA.indices)


par(mfrow=c(1,1))

# plot the original result (weekly observation frequency)
time.rng = c(1,length(time)) ## adjust to zoom in and out
out <- as.matrix(jags.out.original)

ci <- apply(exp(out[,7:ncol(out)]),2,quantile,c(0.025,0.5,0.975))

plot(time,ci[2,],type='n',ylim=range(y,na.rm=TRUE),ylab="Soil Moisture (cm^3/cm^3)",xlab='Date',xlim=time[time.rng], main='SoilMoisturePrecipFusion')
## adjust x-axis label to be monthly if zoomed
# if(diff(time.rng) < 100){ 
#   axis.Date(1, at=seq(time[time.rng[1]],time[time.rng[2]],by='month'), format = "%Y-%m")
# }
ciEnvelope(time,(ci[1,]),(ci[3,]),col="lightBlue")
points(time,y,pch="+",cex=0.5)
points(time[1:20],y[1:20],pch="o",col="red",cex=2)
points(time,p/1000,pch="o",col="blue",cex=1)
points(time,n/2,pch="o",col="green",cex=1)
lines(time,ci[2,])

#Save output
file_name = 'Jags.out.file'
save(ci, file = file_name)
