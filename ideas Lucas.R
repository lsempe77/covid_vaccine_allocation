library(nimue)
library(squire)
library(tidyverse)

#

# Ruta

# 1) Estimar exceso de mortalidad por edades. Eso lo hago mirando primero a Arielinski (Total - Covid), 
#y si hay subregistro,  usando proporciones de Acosta.

# 2) Estimar casos como punto de partida para # de infecciones.
# Dado que tengo el IFR, a partir de 1) se puede estimar mejor infecciones (comparar con Acosta).

# 3) Los pasos anteriores (1 y 2) sirven para establecer parametros iniciales de modelo de vacunacion

# 4) Falta definir porcentaje de vacunados (por edad?).No he visto base de datos.

# 5) Escoger los paises con mayor poblacion o con mayor exceso de mortalidad o con mejor data?

# 6) Usar el modelo de vacunacion, estimando algunos parametros de R0 y con la logica contrafactual. 
# Eso da el numero de infectados y muertos que se pueden reducir.




library(tabulizer)

IFR<-extract_tables("Report34.pdf",11)

IFR <- as.data.frame(do.call(rbind, IFR))

IFR

# table headers get extracted as rows with bad formatting. Dump them.
IFR <- as.data.frame(IFR[3:nrow(IFR), ])

# Column names
headers <- c('Age', 'IFR')

# Apply custom column names
names(IFR) <- headers

IFR<- IFR[1:19,1:2]


t<-IFR %>% separate(IFR,c("A","B"), sep = "(, )") %>% 
  separate(A, c("IFR","l"), sep = "( )") 

t<-t[,1:2]

k <- str_extract_all(IFR$IFR, "\\([^()]+\\)")
# Remove parenthesis
k <- substring(k, 2, nchar(k)-1) %>% as.data.frame()
names(k)<-"CI"

IFR.f <- t %>% bind_cols(k) %>% 
  separate(CI,c("IFR.low","IFR.up"), sep = ", ") %>% mutate(Age=c(0,5,10,15,20,25,
                                                                  30,35,40,45,50,
                                                                  55,60,65,70,75,80,
                                                                  85,90)) %>%
  mutate (Age = case_when (Age>= 80 ~ 80, T ~ as.double(Age)),
          Age = as.factor(Age),
          IFR = as.numeric(IFR),
          IFR.low = as.numeric(IFR.low),
          IFR.up = as.numeric(IFR.up) ) %>%
  group_by(Age) %>% 
  mutate (IFR = mean(IFR,na.rm = T),
          IFR.low=mean(IFR.low,na.rm = T),
          IFR.up=mean(IFR.up,na.rm = T)) %>% distinct()


######

excess.mortality <- read.csv("excess-mortality.csv")


variable.names(excess.mortality)

excess.mortality.Peru <- excess.mortality %>% filter(Country=="Peru")




#######

library(osfr)
library(covidAgeData)

osf_retrieve_file("7tnfh") %>%
  osf_download(conflicts = "overwrite")

Output_5 <-  read_csv("Output_5.zip",
                       skip = 3,
                       col_types = "ccccciiddd")
# convert to date class

Output_5 <-
  Output_5 %>%
  mutate(Date = lubridate::dmy(Date))

table(Output_5$Age)

pa<-Output_5 %>% mutate (Age = case_when (Age>= 80 ~ 80, T ~ as.double(Age))) %>% 
    filter(Country == "Peru",
         Region == "All",
         Sex == "b",
         Date >= lubridate::dmy("01.04.2020")) %>%
  group_by(Age,Date) %>%
     summarise(Deaths=sum(Deaths,na.rm = T),
            Cases=sum(Cases,na.rm = T)) %>% group_by(Age) %>%
  filter(Deaths == max(Deaths)) %>% distinct(Deaths)

write.csv(pa,"excessperuage.csv")

pa2<-Output_5 %>% mutate (Age = case_when (Age>= 80 ~ 80, T ~ as.double(Age))) %>% 
  filter(Country == "Peru",
         Region == "All",
         Sex == "b",
         Date >= lubridate::dmy("01.04.2020")) %>%
  group_by(Age,Date) %>%
  summarise(Deaths=sum(Deaths,na.rm = T),
            Cases=sum(Cases,na.rm = T)) %>% group_by(Age) %>%
  filter(Cases == max(Cases)) %>% distinct(Cases)



pa3<- pa %>% bind_cols(pa2[2]) %>% mutate(cfr=Deaths/Cases*100) %>% 
  bind_cols(IFR.f[2:4]) %>% mutate(dif=cfr-IFR)



pa3 %>% ungroup() %>%
  summarise(d=sum(Deaths))

variable.names(excess.mortality)

excess.mortality %>% arrange(-Excess.deaths) %>%
  ggplot() + geom_point(aes(Undercount.ratio,Excess.deaths))




###



###

init <- nimue:::init(squire::get_population("Peru")$n, seeding_cases = 20000)

# our susceptibles
S_0 <- init$S_0

# let's say 90% already vaccinated in over 15s
prop <- 0.9

# let's then distribute vaccines equally over the vaccinated class
S_0[-(1:3),4] <- round(S_0[-(1:3),1] * prop)

# and remember to decrease the number in the unvaccinated susceptible class
S_0[-(1:3),1] <- S_0[-(1:3),1] - S_0[-(1:3),4]

# and update the init
init$S_0 <- S_0

####

# Run the model with an example population and no vaccination
no_vaccine <- run(country = "Peru", init = init, 
                  max_vaccine = 0,
                  tt_R0 = c(0, 184),
                  R0 = c(1.3, 1.2),
                  time_period = 365)

# Format the output selecting infection and deaths
out1 <- format(no_vaccine, compartments = NULL, summaries = c("infections", "deaths"),
               reduce_age = F) %>%
  mutate(Name = "No vaccine")

5727337/7

# Run the determinstic model with an example population and infection-blocking vaccine
infection_blocking <- run(country = "Peru",  init = init, 
                          max_vaccine = 30000,
                          vaccine_efficacy_disease = rep(0, 17),
                          vaccine_efficacy_infection = rep(0.9, 17),
                          tt_R0 = c(0, 184),
                          R0 = c(1.3, 1.2),
                          time_period = 365)
# Format the output selecting infection and deaths
out2 <- format(infection_blocking, compartments = NULL, summaries = c("infections", "deaths"),
               reduce_age = F) %>%
  mutate(Name = "Infection blocking")

# Run the determinstic model with an example population and anti-disease vaccine
disease_blocking <- run(country = "Peru",  
                        max_vaccine = 30000,init = init, 
                        vaccine_efficacy_disease = rep(0.9, 17),
                        vaccine_efficacy_infection = rep(0, 17) ,
                        tt_R0 = c(0, 184),
                        R0 = c(1.3, 1.2),
                        time_period = 365)

# Format the output selecting infection and deaths
out3 <- format(disease_blocking, compartments = NULL, summaries = c("infections", "deaths"),
               reduce_age = F) %>%
  mutate(Name = "Disease blocking")

summary(out3)

out1 %>% filter(compartment=="deaths")%>%
  ggplot(aes(x = t, y = value)) +
  geom_line(size = 1) +
  facet_wrap(~ age_group, scales = "free_y", ncol = 2) +
  xlim(0, 200) +
  xlab("Time") + 
  theme_bw()


out1 %>% filter(compartment=="deaths" & !is.na(value)) %>% group_by(age_group)%>%
  summarise(c=cumsum(value),c=max(c)) %>% distinct(c) %>% ungroup %>% summarise(t=sum(c))

out2 %>% filter(compartment=="deaths" & !is.na(value)) %>% group_by(age_group)%>%
  summarise(c=cumsum(value),c=max(c)) %>% distinct(c) %>% ungroup %>% summarise(t=sum(c))

out3 %>% filter(compartment=="deaths" & !is.na(value)) %>% group_by(age_group)%>%
  summarise(c=cumsum(value),c=max(c)) %>% distinct(c) %>% ungroup %>% summarise(t=sum(c))


# Create plot data.frame
pd <- bind_rows(out1, out2, out3)
# Plot outputs
ggplot(pd, aes(x = t, y = value, group = Name, col = Name)) +
  geom_line(size = 1) +
  facet_wrap(~ compartment, scales = "free_y", ncol = 2) +
  xlim(0, 200) +
  xlab("Time") + 
  theme_bw()

variable.names(out3)

out3 %>% filter(compartment=="deaths" & replicate == 1 & !is.na(value)) %>%
summarise(c=cumsum(value),c=max(c)) %>% distinct(c)
